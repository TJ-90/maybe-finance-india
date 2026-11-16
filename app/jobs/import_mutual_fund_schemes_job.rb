# Runs nightly (see config/schedule.yml), after AMFI has published the day's NAVs.
#
# 1. Downloads AMFI's NAVAll.txt and upserts every scheme with its latest NAV (powers fund discovery and search)
# 2. Records the latest NAV as a price for mutual fund securities we already track
#    (MutualFundScheme.import_rows! also relinks offline securities that a CAS import created under an ISIN)
class ImportMutualFundSchemesJob < ApplicationJob
  queue_as :scheduled

  def perform
    amfi = Provider::Registry.get_provider(:amfi)

    if amfi.nil?
      Rails.logger.info("Indian market data is disabled, skipping AMFI scheme import")
      return
    end

    response = amfi.fetch_schemes

    unless response.success?
      Rails.logger.warn("Could not import AMFI schemes: #{response.error.message}")
      Sentry.capture_message("AMFI scheme import failed: #{response.error.message}", level: :warning)
      return
    end

    MutualFundScheme.import_rows!(response.data)
    MutualFundScheme.record_latest_prices!
  end
end
