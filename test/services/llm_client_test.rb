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

  test "raises on invalid JSON content and unreachable hosts" do
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: { choices: [ { message: { content: "not json" } } ] }.to_json)
    assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ], json: true) }

    stub_request(:post, @endpoint).to_raise(Errno::ECONNREFUSED)
    error = assert_raises(Llm::Error) { @client.chat([ { role: "user", content: "Hi" } ]) }
    assert_match "Couldn't reach", error.message
  end
end
