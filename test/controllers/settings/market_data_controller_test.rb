require "test_helper"

class Settings::MarketDataControllerTest < ActionDispatch::IntegrationTest
  test "shows provider status and the last NAV date" do
    sign_in users(:family_admin)

    get settings_market_data_url

    assert_response :success
    assert_match "AMFI NAVAll.txt", response.body
    assert_match "Yahoo Finance", response.body
    assert_match "Frankfurter", response.body
    assert_match "Last NAV date", response.body
    assert_select "input[type=file][name=nav_file]"
  end

  test "admin can upload a NAVAll.txt" do
    sign_in users(:family_admin)

    assert_difference "MutualFundScheme.count", 13 do
      patch settings_market_data_url, params: { nav_file: fixture_file_upload("navall_sample.txt", "text/plain") }
    end

    assert_redirected_to settings_market_data_url
    assert_match "Imported 16 mutual fund schemes", flash[:notice]
    assert_equal Date.new(2026, 11, 1), MutualFundScheme.last_nav_date
  end

  test "rejects a file that is not a NAVAll.txt" do
    sign_in users(:family_admin)

    assert_no_difference "MutualFundScheme.count" do
      patch settings_market_data_url, params: { nav_file: Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "x.txt") }
    end

    assert_redirected_to settings_market_data_url
    assert_match "NAVAll", flash[:alert]
  end

  test "requires a file" do
    sign_in users(:family_admin)

    patch settings_market_data_url

    assert_redirected_to settings_market_data_url
    assert flash[:alert].present?
  end

  test "members cannot upload" do
    sign_in users(:family_member)

    assert_no_difference "MutualFundScheme.count" do
      patch settings_market_data_url, params: { nav_file: fixture_file_upload("navall_sample.txt", "text/plain") }
    end

    assert_redirected_to settings_market_data_url
    assert_match "admin", flash[:alert]
  end
end
