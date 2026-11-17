# Same prompt and schema as Provider::Openai::AutoMerchantDetector, over Chat Completions
class Provider::OpenaiCompatible::AutoMerchantDetector < Provider::Openai::AutoMerchantDetector
  def auto_detect_merchants
    json = Provider::OpenaiCompatible::JsonCompletion.new(
      client,
      model: model,
      system: instructions,
      user: developer_message,
      schema: json_schema,
      schema_name: "auto_detect_personal_finance_merchants"
    ).call

    build_response(Array(json["merchants"]).select { |item| item.is_a?(Hash) })
  end
end
