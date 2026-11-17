# Checks a connection with a cheap call: GET /models, or a 1-token completion when the server has no
# /models endpoint. Messages are written here and never include the API key or provider error bodies.
class AiProviderSetting::ConnectionTester
  def initialize(config)
    @config = config
  end

  # => ["ok" | "error", message]
  def call
    client = config.client

    begin
      models = client.models.list
      ids = Array(models.is_a?(Hash) ? models["data"] : nil).filter_map { |m| m["id"] if m.is_a?(Hash) }
      return [ "ok", success_message(ids) ]
    rescue Faraday::ResourceNotFound, Faraday::ClientError => error
      status = error.response&.dig(:status)
      raise unless [ 404, 405, 501 ].include?(status)
      # /models is not supported here: fall through to a completion
    end

    client.chat(parameters: { model: config.chat_model, messages: [ { role: "user", content: "Hi" } ], max_tokens: 1 })
    [ "ok", "Connected to #{config.host}. Model #{config.chat_model} responded." ]
  rescue Faraday::Error => error
    [ "error", Provider::LlmErrors.message_for(error, host: config.host) ]
  rescue StandardError => error
    Rails.logger.warn("AI connection test failed: #{error.class}")
    [ "error", "Could not reach #{config.host}" ]
  end

  private
    attr_reader :config

    def success_message(ids)
      message = "Connected to #{config.host}."
      if ids.any? && !model_listed?(ids)
        message += " Note: #{config.chat_model} is not in the provider's model list. Check the model name."
      end
      message
    end

    def model_listed?(ids)
      ids.any? { |id| id == config.chat_model || id.start_with?("#{config.chat_model}:") || id.end_with?("/#{config.chat_model}") }
    end
end
