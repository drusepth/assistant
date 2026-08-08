require "test_helper"

class LlmClientTest < ActiveSupport::TestCase
  setup do
    @client = Llm::Client.new(base_url: "https://api.openai.com/v1", api_key: "test-key", model: "gpt-4o-mini")
    @endpoint = "https://api.openai.com/v1/chat/completions"
  end

  test "chat returns message content" do
    stub_request(:post, @endpoint)
      .with(headers: { "Authorization" => "Bearer test-key" })
      .to_return(status: 200, body: { choices: [ { message: { content: "Hello!" } } ] }.to_json)

    assert_equal "Hello!", @client.chat([ { role: "user", content: "Hi" } ])
  end

  test "chat with json: true parses the content and requests a JSON object" do
    stub_request(:post, @endpoint)
      .with(body: hash_including("response_format" => { "type" => "json_object" }))
      .to_return(status: 200, body: { choices: [ { message: { content: '{"answer":42}' } } ] }.to_json)

    assert_equal({ "answer" => 42 }, @client.chat([ { role: "user", content: "Hi" } ], json: true))
  end

  test "raises a friendly error on provider errors" do
    stub_request(:post, @endpoint)
      .to_return(status: 401, body: { error: { message: "Incorrect API key provided" } }.to_json)

    error = assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ]) }
    assert_match "401", error.message
    assert_match "Incorrect API key", error.message
  end

  test "router-style providers: model omitted when nil, extra params included" do
    client = Llm::Client.new(base_url: "https://api.chromagolem.com/v1", api_key: "cg-key",
      extra_params: { client_id: "household_1" })

    stub_request(:post, "https://api.chromagolem.com/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer cg-key" }) { |request|
        body = JSON.parse(request.body)
        !body.key?("model") && body["client_id"] == "household_1"
      }
      .to_return(status: 200, body: { choices: [ { message: { content: "Hi!" } } ] }.to_json)

    assert_equal "Hi!", client.chat([ { role: "user", content: "Hi" } ])
  end

  test "classifies failures the retry policy can act on" do
    # Permanent: the request itself is wrong and will be wrong next time too.
    { 400 => "Bad request", 401 => "Incorrect API key", 403 => "Forbidden", 404 => "No such model" }.each do |status, message|
      stub_request(:post, @endpoint).to_return(status: status, body: { error: { message: message } }.to_json)

      error = assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ]) }
      assert_not_kind_of Llm::TransientError, error, "#{status} should not be retried"
    end

    # Transient: the request was fine, the provider just couldn't answer now.
    [ 408, 409, 425, 429, 500, 502, 503, 504 ].each do |status|
      stub_request(:post, @endpoint).to_return(status: status, body: "busy")

      assert_raises(Llm::TransientError, "#{status} should be retried") do
        @client.chat([ { role: "user", content: "Hi" } ])
      end
    end
  end

  test "transport failures are transient, an incompatible endpoint is not" do
    stub_request(:post, @endpoint).to_raise(Errno::ECONNREFUSED)
    assert_raises(Llm::TransientError) { @client.chat([ { role: "user", content: "Hi" } ]) }

    # A response with no choices array means this isn't an OpenAI-compatible
    # endpoint at all — retrying can't fix that.
    stub_request(:post, @endpoint).to_return(status: 200, body: { unexpected: true }.to_json)
    error = assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ]) }
    assert_not_kind_of Llm::TransientError, error
    assert_match "unexpected response shape", error.message
  end

  test "salvages JSON the model wrapped in a markdown fence" do
    fenced = "```json\n{\"answer\": 42}\n```"
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: fenced } } ] }.to_json)

    assert_equal({ "answer" => 42 }, @client.chat([ { role: "user", content: "Hi" } ], json: true))
  end

  test "salvages JSON the model wrapped in prose" do
    chatty = "Here is the plan you asked for:\n\n{\"steps\": [{\"title\": \"Call the clinic\"}]}\n\nGood luck!"
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: chatty } } ] }.to_json)

    assert_equal({ "steps" => [ { "title" => "Call the clinic" } ] },
      @client.chat([ { role: "user", content: "Hi" } ], json: true))
  end

  test "braces alone are not enough — unsalvageable content is still transient" do
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: "set {a: b} then done" } } ] }.to_json)

    assert_raises(Llm::TransientError) { @client.chat([ { role: "user", content: "Hi" } ], json: true) }
  end

  test "invalid JSON is transient, because another sample often parses" do
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: "not json" } } ] }.to_json)

    assert_raises(Llm::TransientError) { @client.chat([ { role: "user", content: "Hi" } ], json: true) }
  end

  test "raises on invalid JSON content and unreachable hosts" do
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: "not json" } } ] }.to_json)
    assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ], json: true) }

    stub_request(:post, @endpoint).to_raise(Errno::ECONNREFUSED)
    error = assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ]) }
    assert_match "Couldn't reach", error.message
  end
end
