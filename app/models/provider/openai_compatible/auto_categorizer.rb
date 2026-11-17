# Same prompt and schema as Provider::Openai::AutoCategorizer, over Chat Completions
class Provider::OpenaiCompatible::AutoCategorizer < Provider::Openai::AutoCategorizer
  def auto_categorize
    json = Provider::OpenaiCompatible::JsonCompletion.new(
      client,
      model: model,
      system: instructions,
      user: developer_message,
      schema: json_schema,
      schema_name: "auto_categorize_personal_finance_transactions"
    ).call

    build_response(Array(json["categorizations"]).select { |item| item.is_a?(Hash) })
  end
end
