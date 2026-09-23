require "net/http"

module Llm
  # The one model adapter (D10): OpenAI-compatible chat completions over
  # plain Net::HTTP. No vendor gem — ~80 auditable lines we own. Works with
  # OpenAI, OpenRouter, Groq, Ollama, llama.cpp, LM Studio by changing
  # base_url; swapping remote for local is configuration, not code.
  class Client
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120 # local models can be slow; be patient

    # Statuses that say "not now" rather than "not ever": rate limits, a
    # gateway hiccup, a local model still loading. Everything else in the 4xx
    # range is a request or configuration problem that will fail identically
    # on the next attempt, so it's raised as a permanent Llm::Error.
    RETRYABLE_STATUSES = %w[ 408 409 425 429 500 502 503 504 ].freeze

    # Connection-level failures are transient by definition — nothing about the
    # request was rejected, it never got an answer.
    TRANSPORT_ERRORS = [
      Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ENETUNREACH, Errno::EPIPE, SocketError, OpenSSL::SSL::SSLError
    ].freeze

    # Providers that ignore response_format still answer in JSON when asked
    # plainly — Anthropic's compatibility layer documents the field as ignored,
    # so this is how json: true reaches Claude. Appended to the last user
    # message rather than sent as a system message: Anthropic hoists every
    # system message to the front of the conversation, which is the worst
    # place for a formatting rule to sit.
    JSON_INSTRUCTION =
      "Respond with a single raw JSON object and nothing else — no prose before or after it, " \
      "and no markdown code fence.".freeze

    # model may be nil for router-style providers that pick the model
    # server-side; extra_params are provider-specific body additions
    # (e.g. Chroma Golem's client_id). json_mode and max_tokens come from the
    # provider preset — see ModelProfile::PROVIDERS.
    def initialize(base_url:, api_key:, model: nil, extra_params: {}, json_mode: :response_format, max_tokens: nil)
      @base_url = base_url.chomp("/")
      @api_key = api_key
      @model = model
      @extra_params = extra_params
      @json_mode = json_mode
      @max_tokens = max_tokens
    end

    # messages: [{role:, content:}, ...]. With json: true, asks the server
    # for a JSON object response and returns the parsed Hash; otherwise
    # returns the raw content String.
    def chat(messages, json: false, temperature: 0.2)
      prompt_json = json && @json_mode == :prompt
      messages = with_json_instruction(messages) if prompt_json

      body = { messages: messages, temperature: temperature, **@extra_params }
      body[:model] = @model if @model
      body[:max_tokens] = @max_tokens if @max_tokens
      body[:response_format] = { type: "json_object" } if json && !prompt_json

      payload = post("/chat/completions", body)
      content = extract_content(payload)
      json ? parse_json(content, payload.dig("choices", 0, "finish_reason")) : content
    end

    private
      # Appends the instruction to the last user turn, in place. Content is
      # either a String or the OpenAI multi-part array (a vision call carries
      # {type: "text"} and {type: "image_url"} parts) — the instruction has to
      # land as text either way. With no user turn at all there's nowhere
      # natural to put it, so add one.
      def with_json_instruction(messages)
        index = messages.rindex { |message| (message[:role] || message["role"]).to_s == "user" }
        return messages + [ { role: "user", content: JSON_INSTRUCTION } ] unless index

        messages = messages.dup
        message = messages[index]
        key = message.key?(:content) ? :content : "content"
        content = message[key]

        messages[index] = message.merge(key =>
          content.is_a?(Array) ?
            content + [ { type: "text", text: JSON_INSTRUCTION } ] :
            "#{content}\n\n#{JSON_INSTRUCTION}")
        messages
      end

      def post(path, body)
        uri = URI("#{@base_url}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = Net::HTTP.start(uri.hostname, uri.port,
          use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          error_class = RETRYABLE_STATUSES.include?(response.code) ? TransientError : Error
          raise error_class, "The model provider returned #{response.code}: #{error_message(response.body)}"
        end

        JSON.parse(response.body)
      rescue *TRANSPORT_ERRORS => e
        raise TransientError, "Couldn't reach the model provider: #{e.message}"
      end

      # Structural, not flaky: a response without a choices array means the
      # endpoint isn't OpenAI-compatible, which retrying won't change.
      def extract_content(payload)
        payload.dig("choices", 0, "message", "content") or
          raise Error, "The model provider returned an unexpected response shape."
      end

      # Flaky, not structural: the endpoint spoke the right protocol and the
      # model simply sampled badly. Another draw often parses.
      def parse_json(content, finish_reason)
        JSON.parse(content)
      rescue JSON::ParserError
        embedded_json(content) or
          raise(TransientError, "The model returned invalid JSON (#{reply_shape(content, finish_reason)}). " \
            "Reply began: #{reply_preview(content)}")
      end

      # Providers that ignore response_format — local models especially — often
      # wrap perfectly valid JSON in a markdown fence or a sentence of prose,
      # and retrying yields the same wrapping every time. The object is still
      # in there: take the outermost {...} or [...] and try again.
      def embedded_json(content)
        embedded = content[/\{.*\}|\[.*\]/m]
        JSON.parse(embedded) if embedded
      rescue JSON::ParserError
        nil
      end

      # This message lands in the /admin error log, so it quotes only a short
      # preview, not the full reply — a reply echoes the private item it was
      # about, and the first lines are where formatting bugs (a fence, a
      # preamble sentence) show themselves anyway. The shape facts cover the
      # rest; finish_reason "length" is the tell for a reply truncated by the
      # provider's token limit, the one invalid-JSON cause that no amount of
      # retrying or salvaging fixes.
      def reply_shape(content, finish_reason)
        shape = [ "#{content.length} chars" ]
        shape << "cut off by the token limit (finish_reason: length)" if finish_reason == "length"
        shape << "opens with a markdown fence" if content.lstrip.start_with?("```")
        shape << (content.include?("{") || content.include?("[") ?
          "contains an unparseable {...} block" : "contains no JSON at all")
        shape.join(", ")
      end

      # inspect, so a leading fence or stray whitespace is visible verbatim
      # ("```json\n{\"steps\"…") instead of dissolving into the log's layout.
      def reply_preview(content)
        content.lines.first(3).join.truncate(200).inspect
      end

      # Error bodies only loosely follow OpenAI's {"error": {"message": ...}}:
      # some providers send {"error": "text"}, Gemini's compatibility layer
      # wraps the object in an array, and proxies send plain text or HTML.
      # Whatever the shape, this must never raise — it runs while reporting
      # the provider's real failure, and a crash here would bury it.
      def error_message(body)
        provider_message(JSON.parse(body)).presence || body.to_s.truncate(200)
      rescue JSON::ParserError
        body.to_s.truncate(200)
      end

      def provider_message(payload)
        case payload
        when Array then provider_message(payload.first)
        when Hash
          error = payload["error"]
          case error
          when Hash then error["message"].presence&.to_s || provider_message(error)
          when String then error
          else payload["message"].is_a?(String) ? payload["message"] : nil
          end
        when String then payload
        end
      end
  end
end
