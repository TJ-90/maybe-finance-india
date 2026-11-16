# India edition: amounts without an explicit currency default to INR.
Rails.application.config.after_initialize do
  Money.default_currency = "INR"
end
