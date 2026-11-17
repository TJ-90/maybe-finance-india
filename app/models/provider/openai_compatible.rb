# LLM provider for OpenRouter and any OpenAI-compatible server (Ollama, LM Studio, Groq, Together, vLLM...).
# Uses the Chat Completions API (`/chat/completions`), unlike Provider::Openai which uses the Responses API.
#
# Unverified against live services: tests stub HTTP. Streaming tool-call formats vary a little between
# servers (see ChatCompletionsStream), so the first run against a given server is a test.
class Provider::OpenaiCompatible < Provider
  include LlmConcept

  Error = Class.new(Provider::Error)

  MAX_HISTORY_MESSAGES = 20

  attr_reader :chat_model, :fast_model, :config

  def initialize(config)
    @config = config
    @client = config.client
    @chat_model = config.chat_model
    @fast_model = config.fast_model
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response(error_transformer: error_transformer) do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(client, transactions: transactions, user_categories: user_categories, model: fast_model).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response(error_transformer: error_transformer) do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(client, transactions: transactions, user_merchants: user_merchants, model: fast_model).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil, history: [])
    with_provider_response(error_transformer: error_transformer) do
      messages = build_messages(prompt, instructions: instructions, function_results: function_results, history: history)
      tools = build_tools(functions)

      parameters = { model: model, messages: messages }
      if tools.any?
        parameters[:tools] = tools
        # Follow-up calls only summarise tool results (see Assistant::Responder), so tools stay declared
        # for servers that insist on it, but the model is told not to call them again.
        parameters[:tool_choice] = "none" if function_results.any?
      end

      if streamer.present?
        stream = ChatCompletionsStream.new(streamer)
        client.chat(parameters: parameters.merge(stream: stream.proc))
        stream.finish!
      else
        raw = client.chat(parameters: parameters)
        raise Error, "The provider returned an unexpected response" unless raw.is_a?(Hash)

        ChatCompletionsParser.new(raw).parsed
      end
    end
  end

  private
    attr_reader :client

    def build_messages(prompt, instructions:, function_results:, history:)
      messages = []
      messages << { role: "system", content: instructions } if instructions.present?

      history.last(MAX_HISTORY_MESSAGES).each do |item|
        next if item[:content].blank?

        messages << { role: item[:role], content: item[:content] }
      end

      messages << { role: "user", content: prompt }

      if function_results.any?
        messages << {
          role: "assistant",
          content: nil,
          tool_calls: function_results.map do |result|
            {
              id: result[:call_id],
              type: "function",
              function: { name: result[:name], arguments: result[:arguments].presence || "{}" }
            }
          end
        }

        function_results.each do |result|
          output = result[:output]
          messages << { role: "tool", tool_call_id: result[:call_id], content: output.is_a?(String) ? output : output.to_json }
        end
      end

      messages
    end

    # No `strict`: many compatible servers reject it
    def build_tools(functions)
      functions.map do |fn|
        { type: "function", function: { name: fn[:name], description: fn[:description], parameters: fn[:params_schema] } }
      end
    end

    def error_transformer
      ->(error) do
        if error.is_a?(Provider::Error)
          error
        elsif error.is_a?(Faraday::Error)
          Error.new(
            Provider::LlmErrors.message_for(error, host: config.host, api_key: config.api_key, include_detail: true)
          )
        else
          Error.new(Provider::LlmErrors.scrub(error.message, config.api_key))
        end
      end
    end
end
