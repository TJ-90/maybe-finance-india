class Investment < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "demat" => { short: "Demat", long: "Demat Account" },
    "mutual_fund" => { short: "Mutual Fund", long: "Mutual Fund" },
    "nps_tier1" => { short: "NPS Tier I", long: "NPS Tier I" },
    "nps_tier2" => { short: "NPS Tier II", long: "NPS Tier II" },
    "ulip" => { short: "ULIP", long: "ULIP" },
    "pms_aif" => { short: "PMS/AIF", long: "PMS / AIF" },
    "brokerage" => { short: "Brokerage", long: "Brokerage" },
    "angel" => { short: "Angel", long: "Angel" }
  }.freeze

  # Subtypes that never hold cash. Purchases are paid from a bank account, so the account is holdings-only.
  NO_CASH_SUBTYPES = %w[mutual_fund nps_tier1 nps_tier2 ulip].freeze

  # `tracks_cash` false means a holdings-only account: trades do not move cash, cash stays 0 and
  # the balance is the market value of the holdings. See Balance::BaseCalculator.
  def self.tracks_cash_by_default?(subtype)
    NO_CASH_SUBTYPES.exclude?(subtype.to_s)
  end

  class << self
    def color
      "#1570EF"
    end

    def classification
      "asset"
    end

    def icon
      "line-chart"
    end
  end
end
