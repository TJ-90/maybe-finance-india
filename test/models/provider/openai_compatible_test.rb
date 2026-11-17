require "test_helper"

class Provider::OpenaiCompatibleTest < ActiveSupport::TestCase
  KEY = "or-secret-key-9876"
  URL = "https://openrouter.ai/api/v1/chat/completions"

  setup do
    @config = AiProviderSetting.new(provider: "openrouter", api_key: KEY).to_llm_config
    @provider = Provider::OpenaiCompatible.new(@config)
    @functions = [ { name: "get_net_worth", description: "Net worth", params_schema: { type: "object", properties: {}, required: [], additionalProperties: false }, strict: true } ]
  end

  test "non-streaming reply" do
    stub_request(:post, URL).to_return(json_response(completion("Hello there")))

    response = @provider.chat_response("Hi", model: "openai/gpt-4.1", instructions: "Be brief", history: [ { role: "user", content: "Earlier" }, { role: "assistant", content: "Answer" } ])

    assert response.success?
    assert_equal "Hello there", response.data.messages.first.output_text
    assert_empty response.data.function_requests

    assert_requested(:post, URL) do |req|
      body = JSON.parse(req.body)
      assert_equal "Bearer #{KEY}", req.headers["Authorization"]
      assert_equal Rails.application.config.x.product_name, req.headers["X-Title"]
      assert_equal %w[system user assistant user], body["messages"].map { |m| m["role"] }
      assert_equal "Hi", body["messages"].last["content"]
      assert_nil body["stream"]
      true
    end
  end

  test "non-streaming tool call is parsed" do
    stub_request(:post, URL).to_return(json_response(tool_completion))

    response = @provider.chat_response("Net worth?", model: "m", functions: @functions)
    request = response.data.function_requests.first

    assert_equal "call_1", request.call_id
    assert_equal "get_net_worth", request.function_name
    assert_equal "{}", request.function_args
  end

  test "streaming reply emits text deltas then one response" do
    sse = sse_body([ delta(content: "Hel"), delta(content: "lo"), delta({}, finish: "stop"), { "id" => "x", "choices" => [] } ])
    stub_request(:post, URL).to_return(status: 200, body: sse, headers: { "Content-Type" => "text/event-stream" })

    chunks = []
    response = @provider.chat_response("Hi", model: "m", streamer: proc { |c| chunks << c })

    assert response.success?
    assert_equal [ "Hel", "lo" ], chunks.select { |c| c.type == "output_text" }.map(&:data)
    final = chunks.select { |c| c.type == "response" }
    assert_equal 1, final.size
    assert_equal "Hello", final.first.data.messages.first.output_text
    assert_equal final.first.data, response.data
  end

  test "tool call split across chunks, then tool result round trip and final answer" do
    first = sse_body([
      delta(tool_calls: [ { "index" => 0, "id" => "call_9", "type" => "function", "function" => { "name" => "get_net_worth", "arguments" => "" } } ]),
      delta(tool_calls: [ { "index" => 0, "function" => { "arguments" => "{\"as_of" } } ]),
      delta(tool_calls: [ { "index" => 0, "function" => { "arguments" => "\":\"today\"}" } } ]),
      delta({}, finish: "tool_calls")
    ])
    second = sse_body([ delta(content: "Your net worth is "), delta(content: "Rs 10 lakh"), delta({}, finish: "stop") ])

    stub_request(:post, URL)
      .to_return({ status: 200, body: first, headers: { "Content-Type" => "text/event-stream" } },
                 { status: 200, body: second, headers: { "Content-Type" => "text/event-stream" } })

    chunks = []
    first_response = @provider.chat_response("Net worth?", model: "m", functions: @functions, streamer: proc { |c| chunks << c })
    request = first_response.data.function_requests.first

    assert_equal "call_9", request.call_id
    assert_equal "get_net_worth", request.function_name
    assert_equal "{\"as_of\":\"today\"}", request.function_args
    assert_empty chunks.select { |c| c.type == "output_text" }

    result = { call_id: "call_9", name: request.function_name, arguments: request.function_args, output: { amount: 1_000_000 } }
    second_response = @provider.chat_response("Net worth?", model: "m", functions: @functions, function_results: [ result ], streamer: proc { |c| chunks << c })

    assert_equal "Your net worth is Rs 10 lakh", second_response.data.messages.first.output_text

    assert_requested(:post, URL, times: 2)
    assert_requested(:post, URL) do |req|
      body = JSON.parse(req.body)
      next false unless body["messages"].any? { |m| m["role"] == "tool" }

      assistant = body["messages"].find { |m| m["tool_calls"] }
      tool = body["messages"].find { |m| m["role"] == "tool" }
      assert_equal "call_9", assistant["tool_calls"].first["id"]
      assert_equal "get_net_worth", assistant["tool_calls"].first.dig("function", "name")
      assert_equal "call_9", tool["tool_call_id"]
      assert_equal({ "amount" => 1_000_000 }, JSON.parse(tool["content"]))
      assert_equal "none", body["tool_choice"]
      assert_equal true, body["stream"]
      true
    end
  end

  test "tool calls without index or in one chunk still parse" do
    sse = sse_body([
      delta(tool_calls: [ { "id" => "call_a", "function" => { "name" => "get_net_worth", "arguments" => "{}" } } ]),
      delta(tool_calls: [ { "id" => "call_b", "function" => { "name" => "get_net_worth", "arguments" => "{}" } } ])
    ])
    stub_request(:post, URL).to_return(status: 200, body: sse, headers: { "Content-Type" => "text/event-stream" })

    response = @provider.chat_response("x", model: "m", functions: @functions, streamer: proc { })

    assert_equal %w[call_a call_b], response.data.function_requests.map(&:call_id)
  end

  test "maps errors to clear messages without leaking the key" do
    {
      401 => "Invalid API key",
      404 => "Model not found",
      429 => "Rate limit"
    }.each do |status, expected|
      stub_request(:post, URL).to_return(status: status, body: { error: { message: "Bad key #{KEY}" } }.to_json, headers: { "Content-Type" => "application/json" })

      response = @provider.chat_response("Hi", model: "m")

      assert_not response.success?
      assert_kind_of Provider::OpenaiCompatible::Error, response.error
      assert_includes response.error.message, expected
      assert_not_includes response.error.message, KEY
      assert_not_includes response.error.to_json, KEY
    end
  end

  test "network failure says the host could not be reached" do
    stub_request(:post, URL).to_timeout

    response = @provider.chat_response("Hi", model: "m")

    assert_not response.success?
    assert_includes response.error.message, "Could not reach openrouter.ai"
  end

  test "auto categorizes with a chat completions JSON reply" do
    stub_request(:post, URL).to_return(json_response(completion({ categorizations: [ { transaction_id: "1", category_name: "Groceries" }, { transaction_id: "2", category_name: "null" } ] }.to_json)))

    response = @provider.auto_categorize(
      transactions: [ { id: "1", name: "BigBasket" }, { id: "2", name: "xyz" } ],
      user_categories: [ { id: "c1", name: "Groceries", classification: "expense" } ]
    )

    assert response.success?
    assert_equal "Groceries", response.data.first.category_name
    assert_nil response.data.last.category_name

    assert_requested(:post, URL) do |req|
      body = JSON.parse(req.body)
      assert_equal "openai/gpt-4.1-mini", body["model"]
      assert_equal "json_schema", body.dig("response_format", "type")
      true
    end
  end

  test "auto categorize falls back when response_format is rejected and parses fenced JSON" do
    fenced = "Here you go:\n```json\n#{{ categorizations: [ { transaction_id: "1", category_name: "Groceries" } ] }.to_json}\n```"

    stub_request(:post, URL)
      .to_return({ status: 400, body: { error: { message: "response_format unsupported" } }.to_json, headers: { "Content-Type" => "application/json" } },
                 { status: 400, body: { error: { message: "json_object unsupported" } }.to_json, headers: { "Content-Type" => "application/json" } },
                 json_response(completion(fenced)))

    response = @provider.auto_categorize(transactions: [ { id: "1", name: "BigBasket" } ], user_categories: [ { id: "c1", name: "Groceries" } ])

    assert response.success?
    assert_equal "Groceries", response.data.first.category_name
    assert_requested(:post, URL, times: 3)
  end

  test "auto detects merchants" do
    stub_request(:post, URL).to_return(json_response(completion({ merchants: [ { transaction_id: "1", business_name: "Amazon", business_url: "amazon.in" } ] }.to_json)))

    response = @provider.auto_detect_merchants(transactions: [ { id: "1", name: "AMZN" } ], user_merchants: [])

    assert response.success?
    assert_equal "Amazon", response.data.first.business_name
  end

  private
    def json_response(body)
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    def completion(text)
      { id: "chatcmpl-1", model: "m", choices: [ { index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" } ], usage: { total_tokens: 5 } }
    end

    def tool_completion
      { id: "chatcmpl-2", model: "m", choices: [ { index: 0, message: { role: "assistant", content: nil, tool_calls: [ { id: "call_1", type: "function", function: { name: "get_net_worth", arguments: "" } } ] } } ] }
    end

    def delta(fields = {}, finish: nil, **kw)
      delta_fields = fields.merge(kw)
      { "id" => "chatcmpl-s", "model" => "m", "choices" => [ { "index" => 0, "delta" => delta_fields, "finish_reason" => finish } ] }
    end

    def sse_body(chunks)
      chunks.map { |c| "data: #{c.to_json}\n\n" }.join + "data: [DONE]\n\n"
    end
end
