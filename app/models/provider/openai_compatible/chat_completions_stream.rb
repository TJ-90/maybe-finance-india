# Accumulates a streamed Chat Completions response (server-sent chunks) and forwards text deltas to the
# caller as LlmConcept "output_text" chunks. When the stream ends, `finish!` emits one "response" chunk
# and returns its data, matching what Provider::Openai does for the Responses API.
#
# Tool calls arrive in pieces: the first fragment of a call carries its id and name, later fragments only
# carry more of the `arguments` string, all tagged with the call's `index`. Some servers omit `index`
# or send each call whole in one chunk; both are handled.
class Provider::OpenaiCompatible::ChatCompletionsStream
  Chunk = Provider::LlmConcept::ChatStreamChunk
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def initialize(streamer)
    @streamer = streamer
    @text = +""
    @calls = {}
    @last_call_key = nil
    @id = nil
    @model = nil
    @received = false
  end

  def proc
    method(:handle).to_proc
  end

  def finish!
    raise Provider::OpenaiCompatible::Error, "The provider returned no streamed response" unless @received

    requests = @calls.values.filter_map do |call|
      next if call[:name].blank?

      ChatFunctionRequest.new(id: call[:id], call_id: call[:id], function_name: call[:name], function_args: call[:arguments].presence || "{}")
    end

    response = ChatResponse.new(
      id: @id,
      model: @model,
      messages: @text.present? ? [ ChatMessage.new(id: @id, output_text: @text) ] : [],
      function_requests: requests
    )

    @streamer.call(Chunk.new(type: "response", data: response))
    response
  end

  private
    def handle(chunk, *)
      @received = true

      if chunk.is_a?(Hash) && chunk["error"].present?
        error = chunk["error"]
        raise Provider::OpenaiCompatible::Error, "The provider reported an error: #{(error.is_a?(Hash) ? error["message"] : error).to_s.truncate(300)}"
      end

      @id ||= chunk["id"]
      @model ||= chunk["model"]

      choice = Array(chunk["choices"]).first
      return if choice.nil?

      delta = choice["delta"] || {}

      content = delta["content"] || delta["refusal"]
      if content.is_a?(String) && content.present?
        @text << content
        @streamer.call(Chunk.new(type: "output_text", data: content))
      end

      Array(delta["tool_calls"]).each_with_index { |fragment, position| add_tool_call_fragment(fragment, position) }
    end

    def add_tool_call_fragment(fragment, position)
      key = if fragment["index"]
        fragment["index"]
      elsif fragment["id"].present? && !known_id?(fragment["id"])
        "pos-#{@calls.size}"
      else
        @last_call_key || "pos-#{position}"
      end

      call = (@calls[key] ||= { id: nil, name: "", arguments: +"" })
      call[:id] ||= fragment["id"].presence
      call[:id] ||= "call_#{SecureRandom.hex(6)}" if fragment.dig("function", "name").present?
      name = fragment.dig("function", "name").to_s
      call[:name] = name if call[:name].blank? && name.present?
      call[:arguments] << fragment.dig("function", "arguments").to_s
      @last_call_key = key
    end

    def known_id?(id)
      @calls.values.any? { |call| call[:id] == id }
    end
end
