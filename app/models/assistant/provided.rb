module Assistant::Provided
  extend ActiveSupport::Concern

  # The LLM provider for this chat's family (saved AI settings, then instance fallbacks)
  def get_model_provider(_ai_model = nil)
    Provider::Registry.llm_provider(chat.user.family)
  end
end
