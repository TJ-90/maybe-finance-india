require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "login page uses the product name and not Maybe" do
    get new_session_url

    assert_response :success
    assert_select "title", text: /Kosh/
    assert_no_match(/Maybe/, response.body)
  end

  test "PWA manifest uses the product name" do
    get pwa_manifest_url(format: :json)

    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal "Kosh", manifest["name"]
    assert_equal "Kosh", manifest["short_name"]
    assert_no_match(/Maybe/, response.body)
  end

  test "dashboard has no Maybe branding or billing link when Stripe is unconfigured" do
    sign_in users(:family_admin)
    get root_url

    assert_response :success
    assert_no_match(/Maybe Finance|Maybe AI/, response.body)
    assert_no_match(/Billing/, response.body)
  end

  test "mailer sender uses the product name" do
    assert_match(/Kosh/, ApplicationMailer.default[:from])
  end
end
