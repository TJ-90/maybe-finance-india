# Turns HTTP/network failures from an LLM endpoint into short messages that are safe to show.
# The API key is never included: messages are written here (not copied from the exception), and the
# optional provider detail is scrubbed of the key before it is used.
module Provider::LlmErrors
  module_function

  def message_for(error, host:, api_key: nil, include_detail: false)
    status = error.respond_to?(:response) ? error.response&.dig(:status) : nil

    base = case error
    when Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError
      "Could not reach #{host}"
    else
      case status
      when 401 then "Invalid API key"
      when 403 then "The provider refused access. Check the key's permissions"
      when 404 then "Model not found"
      when 429 then "Rate limit or quota exceeded at the provider"
      when 400, 422 then "The provider rejected the request (#{status})"
      when 500..599 then "The provider had a server error (#{status})"
      else "Request to #{host} failed"
      end
    end

    detail = include_detail ? detail_from(error, api_key) : nil
    detail.present? ? "#{base}: #{detail}" : base
  end

  def scrub(text, api_key)
    text = text.to_s
    text = text.gsub(api_key, "[FILTERED]") if api_key.present?
    text
  end

  def detail_from(error, api_key)
    body = error.respond_to?(:response) ? error.response&.dig(:body) : nil
    message = if body.is_a?(Hash)
      err = body["error"]
      err.is_a?(Hash) ? err["message"] : (err || body["message"])
    end

    scrub(message, api_key).truncate(300).presence
  end
end
