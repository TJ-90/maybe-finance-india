# Create OAuth applications for the first-party mobile app
# These are the only OAuth apps that will exist - external developers use API keys

product_name = Rails.application.config.x.product_name

# iOS app. Installs seeded before the rename may still have the old "Maybe iOS" name, so look for both.
ios_app = Doorkeeper::Application.find_by(name: [ "#{product_name} iOS", "Maybe iOS" ]) ||
          Doorkeeper::Application.new(name: "#{product_name} iOS")

ios_app.name = "#{product_name} iOS"
ios_app.redirect_uri = "maybe://oauth/callback" # URL scheme is registered in the mobile app, leave as is
ios_app.scopes = "read_accounts read_transactions read_balances"
ios_app.confidential = false # Public client (mobile app)
ios_app.save!

puts "Created OAuth applications:"
puts "iOS App - Client ID: #{ios_app.uid}"
puts ""
puts "External developers should use API keys instead of OAuth."
