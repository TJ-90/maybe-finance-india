require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "synth configured with ENV" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "123" do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth configured with Setting" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth not configured" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:synth)
    end
  end

  test "Indian market providers are preferred for securities and exchange rates" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil, SYNTH_API_KEY: nil do
      assert_instance_of Provider::IndianMarkets, Provider::Registry.for_concept(:securities).first_provider
      assert_instance_of Provider::Frankfurter, Provider::Registry.for_concept(:exchange_rates).first_provider
      assert_instance_of Provider::Amfi, Provider::Registry.get_provider(:amfi)
    end
  end

  test "Synth is used when Indian market data is disabled and a key is configured" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: "true", SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.for_concept(:securities).first_provider
      assert_instance_of Provider::Synth, Provider::Registry.for_concept(:exchange_rates).first_provider
      assert_nil Provider::Registry.get_provider(:amfi)
    end
  end

  test "no provider is configured when Indian market data is disabled and Synth has no key" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides DISABLE_INDIAN_MARKET_DATA: "true", SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.for_concept(:securities).first_provider
      assert_nil Provider::Registry.for_concept(:exchange_rates).first_provider
    end
  end
end
