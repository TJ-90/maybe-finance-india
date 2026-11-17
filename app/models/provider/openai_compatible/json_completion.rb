# Asks a Chat Completions endpoint for a JSON answer. Servers differ in what they support, so it tries
# `json_schema`, then `json_object`, then plain text (retrying only when the server rejects the request with
# a 400/422), and always parses the text robustly (code fences or chatter around the JSON are tolerated).
# The schema is also written into the prompt so models without structured output still follow it.
class Provider::OpenaiCompatible::JsonCompletion
  Error = Class.new(StandardError)

  def initialize(client, model:, system:, user:, schema:, schema_name:)
    @client = client
    @model = model
    @system = system
    @user = user
    @schema = schema
    @schema_name = schema_name
  end

  def call
    formats = [
      { type: "json_schema", json_schema: { name: schema_name, strict: true, schema: schema } },
      { type: "json_object" },
      nil
    ]

    response = nil
    formats.each_with_index do |format, index|
      response = request(format)
      break
    rescue Faraday::BadRequestError, Faraday::UnprocessableEntityError
      raise if index == formats.size - 1
    end

    usage = response.dig("usage", "total_tokens")
    Rails.logger.info("Tokens used for #{schema_name}: #{usage}") if usage

    self.class.parse_json(response.dig("choices", 0, "message", "content"))
  end

  class << self
    # Parses JSON out of model text: plain JSON, fenced JSON, or JSON surrounded by prose
    def parse_json(text)
      text = text.to_s.strip
      raise Error, "The model returned an empty answer" if text.blank?

      candidates = [ text, text[/```(?:json)?\s*(.*?)```/m, 1], text[/\{.*\}/m] ].compact
      candidates.each do |candidate|
        parsed = JSON.parse(candidate.strip)
        return parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        next
      end

      raise Error, "The model did not return valid JSON"
    end
  end

  private
    attr_reader :client, :model, :system, :user, :schema, :schema_name

    def request(format)
      parameters = {
        model: model,
        messages: [
          { role: "system", content: "#{system}\n\nRespond with ONLY a JSON object matching this JSON schema:\n#{schema.to_json}" },
          { role: "user", content: user }
        ]
      }
      parameters[:response_format] = format if format

      response = client.chat(parameters: parameters)
      raise Error, "The provider returned an unexpected response" unless response.is_a?(Hash)

      response
    end
end
