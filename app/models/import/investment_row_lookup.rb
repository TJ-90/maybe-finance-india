# Shared by the investment imports (CAS PDF, broker tradebook, mutual fund template): finding the
# Security a row refers to, and noticing trades that were imported before.
module Import::InvestmentRowLookup
  extend ActiveSupport::Concern

  ISIN_PATTERN = /\A[A-Z]{2}[A-Z0-9]{9}\d\z/

  private
    # Call before walking the rows, so that a dry run does not use up what the real import needs
    def reset_duplicate_tracking
      @existing_trade_counts = nil
      @seen_external_ids = nil
    end

    # Mutual fund rows (MIC AMFI) go ISIN -> MutualFundScheme -> Security (ticker = AMFI scheme code).
    # Everything else goes ISIN (on the same exchange) -> Security::Resolver.
    # Without `create`, only existing securities are returned.
    def security_for(row, create:)
      @security_cache ||= {}
      cache_key = [ row.isin.presence || row.ticker, row.exchange_operating_mic, create ]
      return @security_cache[cache_key] if @security_cache.key?(cache_key)

      @security_cache[cache_key] = if row.exchange_operating_mic.to_s.upcase == Security::AMFI_MIC
        mutual_fund_security(row, create: create)
      else
        listed_security(row, create: create)
      end
    end

    def mutual_fund_security(row, create:)
      isin = row.isin.to_s.upcase.presence
      scheme = scheme_for(isin, row.ticker)

      if scheme
        existing = Security.find_by(ticker: scheme.scheme_code, exchange_operating_mic: Security::AMFI_MIC)
        return existing if existing || !create

        return Security.create!(
          ticker: scheme.scheme_code,
          exchange_operating_mic: Security::AMFI_MIC,
          name: scheme.name,
          kind: "mutual_fund",
          isin: scheme.isin_growth.presence || isin,
          country_code: "IN"
        )
      end

      existing = isin && Security.find_by(isin: isin)
      return existing if existing || !create

      # Unknown to AMFI data: keep the units under an offline security that carries the scheme name
      Security.create!(
        ticker: isin || row.ticker.to_s.upcase.truncate(40, omission: ""),
        exchange_operating_mic: Security::AMFI_MIC,
        name: row.name.to_s.sub(/\A[^:]+:\s*/, "").presence,
        kind: "mutual_fund",
        isin: isin,
        country_code: "IN",
        offline: true
      )
    end

    def scheme_for(isin, ticker)
      scheme = MutualFundScheme.where(isin_growth: isin).or(MutualFundScheme.where(isin_reinvestment: isin)).first if isin
      scheme ||= MutualFundScheme.find_by(scheme_code: ticker.to_s) if ticker.to_s.match?(/\A\d{4,7}\z/)
      scheme
    end

    def listed_security(row, create:)
      isin = row.isin.to_s.upcase.presence
      mic = row.exchange_operating_mic.to_s.upcase.presence

      found = Security.find_by(isin: isin, exchange_operating_mic: mic) if isin && mic
      return found if found || row.ticker.blank?

      unless create
        return Security.find_by(ticker: row.ticker.to_s.upcase, exchange_operating_mic: mic)
      end

      security = Security::Resolver.new(row.ticker, exchange_operating_mic: mic).resolve
      security.update!(isin: isin) if security && isin && security.isin.blank?
      security
    end

    # True when `row` matches a trade that exists already, and uses that trade up so that several
    # identical lines in one statement all count as new the first time and as duplicates afterwards.
    def already_imported?(account, security, row)
      if row.external_id.present?
        seen_external_ids(account).add?(row.external_id).nil?
      elsif security
        counts = (@existing_trade_counts ||= {})[[ account.id, security.id ]] ||= existing_trade_counts(account, security)
        key = [ row.folio_number.to_s, row.date_iso, row.qty.to_d.round(4) ]
        return false unless counts[key].positive?

        counts[key] -= 1
        true
      else
        false
      end
    end

    def seen_external_ids(account)
      (@seen_external_ids ||= {})[account.id] ||=
        Trade.joins(:entry).where(entries: { account_id: account.id }).where.not(external_id: nil).pluck(:external_id).to_set
    end

    def existing_trade_counts(account, security)
      Trade.joins(:entry)
           .where(security_id: security.id, entries: { account_id: account.id })
           .pluck("trades.folio_number", "entries.date", "trades.qty")
           .each_with_object(Hash.new(0)) do |(folio, date, qty), counts|
        counts[[ folio.to_s, date.iso8601, qty.to_d.round(4) ]] += 1
      end
    end
end
