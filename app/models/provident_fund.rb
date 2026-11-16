class ProvidentFund < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "epf" => { short: "EPF", long: "Employees' Provident Fund" },
    "vpf" => { short: "VPF", long: "Voluntary Provident Fund" },
    "ppf" => { short: "PPF", long: "Public Provident Fund" },
    "ssy" => { short: "SSY", long: "Sukanya Samriddhi Yojana" }
  }.freeze

  # Which key in config/india_small_savings_rates.yml supplies the default rate for each subtype
  RATE_SCHEMES = {
    "epf" => :epf,
    "vpf" => :epf,
    "ppf" => :ppf,
    "ssy" => :ssy
  }.freeze

  validates :interest_rate, numericality: { greater_than_or_equal_to: 0, less_than: 100 }, allow_nil: true
  validates :monthly_contribution, :employer_contribution, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :account_number_last4, format: { with: /\A\d{4}\z/, message: "must be exactly 4 digits" }, allow_blank: true

  after_update_commit :sync_account_later, if: -> { (saved_changes.keys & %w[interest_rate opened_on maturity_date]).any? }

  class << self
    def color
      "#0E9384"
    end

    def icon
      "piggy-bank"
    end

    def classification
      "asset"
    end
  end

  def subtype
    account&.subtype
  end

  # Interest rate in % p.a. on `date`: the account's own override, else the default for its subtype
  def rate_on(date)
    interest_rate || default_rate_on(date)
  end

  def default_rate_on(date)
    scheme = RATE_SCHEMES[subtype]
    scheme && SmallSavingsRates.rate_on(scheme, date)
  end

  # EPF/VPF interest runs on the month-end running balance. PPF/SSY on the balance on the 5th.
  def interest_method
    %w[epf vpf].include?(subtype) ? :monthly_running_balance : :balance_on_fifth
  end

  # The opening balance is the balance on this date (the account's opening date), and interest is
  # computed from here forward, so it must not predate the balance the user typed in.
  def opening_balance_date
    opened_on || Date.current
  end

  def balance_display_name
    "balance"
  end

  def generate_auto_entries!
    ProvidentFund::InterestPoster.new(self).post!
  end

  private
    def sync_account_later
      account&.sync_later
    end
end
