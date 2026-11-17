class Provider::Openai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Openai::Error
  Error = Class.new(Provider::Error)

  attr_reader :chat_model, :fast_model

  # `config` (an LlmConfig) carries the models and endpoint. A bare access token still works and
  # means "api.openai.com with the default models".
  def initialize(access_token, chat_model: "gpt-4.1", fast_model: "gpt-4.1-mini", config: nil)
    @access_token = access_token
    @client = config ? config.client : ::OpenAI::Client.new(access_token: access_token)
    @chat_model = chat_model
    @fast_model = fast_model
  end

  def auto_categorize(transactions: [], user_categories: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      AutoCategorizer.new(
        client,
        transactions: transactions,
        user_categories: user_categories,
        model: fast_model
      ).auto_categorize
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        transactions: transactions,
        user_merchants: user_merchants,
        model: fast_model
      ).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil, history: [])
    with_provider_response(error_transformer: error_transformer) do
      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      collected_chunks = []

      # Proxy that converts raw stream to "LLM Provider concept" stream
      stream_proxy = if streamer.present?
        proc do |chunk|
          parsed_chunk = ChatStreamParser.new(chunk).parsed

          unless parsed_chunk.nil?
            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end
      else
        nil
      end

      raw_response = client.responses.create(parameters: {
        model: model,
        input: chat_config.build_input(prompt),
        instructions: instructions,
        tools: chat_config.tools,
        previous_response_id: usable_previous_response_id(previous_response_id),
        stream: stream_proxy
      })

      # If streaming, Ruby OpenAI does not return anything, so to normalize this method's API, we search
      # for the "response chunk" in the stream and return it (it is already parsed)
      if stream_proxy.present?
        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
        response_chunk.data
      else
        ChatParser.new(raw_response).parsed
      end
    end
  end

  private
    attr_reader :client, :access_token

    # Response ids are specific to the Responses API. An id saved while another provider was in use
    # (e.g. a Chat Completions id) would make OpenAI reject the request.
    def usable_previous_response_id(id)
      id.to_s.start_with?("resp_") ? id : nil
    end

    def error_transformer
      ->(error) do
        message = Provider::LlmErrors.scrub(error.message, access_token)
        details = error.respond_to?(:response) ? Provider::LlmErrors.scrub(error.response&.dig(:body).to_s, access_token) : nil
        Error.new(message, details: details.presence)
      end
    end
end
