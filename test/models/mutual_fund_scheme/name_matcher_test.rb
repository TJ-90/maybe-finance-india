require "test_helper"
require "support/mutual_fund_scheme_test_helper"

class MutualFundScheme::NameMatcherTest < ActiveSupport::TestCase
  include MutualFundSchemeTestHelper
  setup do
    @schemes = create_sigma_schemes
    @matcher = MutualFundScheme::NameMatcher.new
  end

  test "matches a display name to the AMFI scheme, plan and option included" do
    assert_equal @schemes[:nifty_direct], @matcher.match("Sigma Alpha Index Fund Direct Growth")
    assert_equal @schemes[:nifty_regular], @matcher.match("Sigma Alpha Index Fund Regular Growth")
    assert_equal @schemes[:nifty_idcw_direct], @matcher.match("Sigma Alpha Index Fund Direct IDCW")
  end

  test "ignores case, punctuation and filler words" do
    assert_equal @schemes[:nifty_direct], @matcher.match("SIGMA ALPHA INDEX FUND - DIRECT PLAN - GROWTH OPTION")
    assert_equal @schemes[:midcap_direct], @matcher.match("Sigma Mid Cap Fund Direct Growth")
    assert_equal @schemes[:midcap_direct], @matcher.match("Sigma Midcap Direct Plan Growth")
  end

  test "does not mistake a similar fund for the one named" do
    assert_equal @schemes[:next_nifty_direct], @matcher.match("Sigma Alpha Next Index Fund Direct Growth")
  end

  test "a plan or option that disagrees is never matched" do
    MutualFundScheme.where(plan: "regular").update_all(active: false)

    assert_nil MutualFundScheme::NameMatcher.new.match("Sigma Alpha Index Fund Regular Growth")

    MutualFundScheme.where(option: "idcw", plan: "direct").update_all(active: false)
    assert_nil MutualFundScheme::NameMatcher.new.match("Sigma Alpha Index Fund Direct IDCW")
  end

  test "a name without plan and option is ambiguous" do
    assert_nil @matcher.match("Sigma Alpha Index Fund")
  end

  test "unknown or distant names are not matched" do
    assert_nil @matcher.match("Totally Unknown Fund Direct Growth")
    assert_nil @matcher.match("Sigma Gold Fund Direct Growth")
    assert_nil @matcher.match("")
  end

  test "two schemes with the same name make the match ambiguous" do
    @schemes[:midcap_direct].dup.tap { |scheme| scheme.scheme_code = "499999" }.save!

    assert_nil MutualFundScheme::NameMatcher.new.match("Sigma Midcap Fund Direct Growth")
  end

  test "candidates list the agreeing schemes first" do
    codes = @matcher.candidates("Sigma Alpha Index Fund Direct Growth", limit: 3).map { |c| c.scheme.scheme_code }

    assert_equal "400001", codes.first
  end
end
