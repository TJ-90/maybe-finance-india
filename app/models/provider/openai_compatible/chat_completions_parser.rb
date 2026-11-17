# Parses a non-streaming Chat Completions response into LlmConcept objects
class Provider::OpenaiCompatible::ChatCompletionsParser
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def initialize(object)
    @object = object
  end

  def parsed
    message = object.dig("choices", 0, "message") || {}
    text = extract_text(message)

    ChatResponse.new(
      id: object["id"],
      model: object["model"],
      messages: text.present? ? [ ChatMessage.new(id: object["id"], output_text: text) ] : [],
      function_requests: function_requests(message["tool_calls"])
    )
  end

  private
    attr_reader :object

    def extract_text(message)
      content = message["content"]
      text = content.is_a?(Array) ? content.filter_map { |part| part["text"] }.join : content.to_s
      text.presence || message["refusal"].to_s
    end

    def function_requests(tool_calls)
      Array(tool_calls).filter_map do |call|
        name = call.dig("function", "name")
        next if name.blank?

        ChatFunctionRequest.new(
          id: call["id"],
          call_id: call["id"],
          function_name: name,
          function_args: call.dig("function", "arguments").presence || "{}"
        )
      end
    end
end
