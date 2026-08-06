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

      content = extract_content(post("/chat/completions", body))
      json ? parse_json(content) : content
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
      def parse_json(content)
        JSON.parse(content)
      rescue JSON::ParserError
        raise TransientError, "The model returned invalid JSON."
      end

      def error_message(body)
        JSON.parse(body).dig("error", "message") || body.to_s.truncate(200)
      rescue JSON::ParserError
        body.to_s.truncate(200)
      end
  end
end
