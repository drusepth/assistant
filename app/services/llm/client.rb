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

    # model may be nil for router-style providers that pick the model
    # server-side; extra_params are provider-specific body additions
    # (e.g. Chroma Golem's client_id).
    def initialize(base_url:, api_key:, model: nil, extra_params: {})
      @base_url = base_url.chomp("/")
      @api_key = api_key
      @model = model
      @extra_params = extra_params
    end

    # messages: [{role:, content:}, ...]. With json: true, asks the server
    # for a JSON object response and returns the parsed Hash; otherwise
    # returns the raw content String.
    def chat(messages, json: false, temperature: 0.2)
      body = { messages: messages, temperature: temperature, **@extra_params }
      body[:model] = @model if @model
      body[:response_format] = { type: "json_object" } if json

      payload = post("/chat/completions", body)
      content = extract_content(payload)
      json ? parse_json(content, payload.dig("choices", 0, "finish_reason")) : content
    end

    private
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
          raise(TransientError, "The model returned invalid JSON (#{reply_shape(content, finish_reason)}).")
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

      # Diagnosis without disclosure: this message lands in the /admin error
      # log, and a raw reply can echo a private item back (a goal breakdown
      # quotes the goal), so describe the reply's shape rather than quoting
      # it — see AppError. finish_reason "length" is the tell for a reply
      # truncated by the provider's token limit, the one invalid-JSON cause
      # that no amount of retrying or salvaging fixes.
      def reply_shape(content, finish_reason)
        shape = [ "#{content.length} chars" ]
        shape << "cut off by the token limit (finish_reason: length)" if finish_reason == "length"
        shape << "opens with a markdown fence" if content.lstrip.start_with?("```")
        shape << (content.include?("{") || content.include?("[") ?
          "contains an unparseable {...} block" : "contains no JSON at all")
        shape.join(", ")
      end

      def error_message(body)
        JSON.parse(body).dig("error", "message") || body.to_s.truncate(200)
      rescue JSON::ParserError
        body.to_s.truncate(200)
      end
  end
end
