class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name(ENV.fetch("EMAIL_SENDER", "sender@example.com"), Rails.application.config.x.product_name)
  layout "mailer"

  helper_method :product_name

  private
    def product_name
      Rails.application.config.x.product_name
    end
end
