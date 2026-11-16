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
