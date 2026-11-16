# Indicative tax on a set of classified gains, after set-off within the year.
#
# Set-off order: short-term losses against short-term gains, long-term losses against long-term gains,
# then any short-term loss left over against long-term gains. The Sec 112A exemption applies to equity
# LTCG that is left after set-off. Losses are always applied to the highest-rate gains first.
# Not computed: surcharge, cess, 87A rebate, and carry-forward of unabsorbed losses.
class TaxCenter::Estimate
  BUCKETS = %i[stcg_equity ltcg_equity slab ltcg_other exempt].freeze

  Group = Struct.new(:bucket, :term, :rate, :exemption_eligible, :net, keyword_init: true)

  attr_reader :totals, :exemption_limit, :exemption_used, :taxable, :tax, :unabsorbed_short_loss, :unabsorbed_long_loss

  # gains: array of [TaxCenter::Rules::Classification, BigDecimal amount]
  def initialize(gains:, slab_rate:, exemption_limit:)
    @slab_rate = BigDecimal(slab_rate.to_s)
    @exemption_limit = exemption_limit
    @totals = BUCKETS.index_with { BigDecimal("0") }
    gains.each { |classification, amount| @totals[classification.bucket] += amount }

    calculate(gains)
  end

  def exemption_remaining
    [ exemption_limit - exemption_used, 0 ].max
  end

  def total_gain
    totals.values.sum
  end

  private
    def calculate(gains)
      groups = build_groups(gains)
      short = groups.select { |g| g.term == :short }
      long = groups.select { |g| g.term == :long }

      short_loss = absorb(loss_pool(short), positives(short))
      long_loss = absorb(loss_pool(long), positives(long))
      short_loss = absorb(short_loss, positives(long))

      @unabsorbed_short_loss = short_loss
      @unabsorbed_long_loss = long_loss

      eligible = positives(groups.select(&:exemption_eligible))
      @exemption_used = [ eligible.sum(&:net), exemption_limit ].min
      absorb(@exemption_used, eligible)

      remaining = positives(groups)
      @taxable = remaining.sum(&:net)
      @tax = remaining.sum { |g| g.net * effective_rate(g) / 100 }
    end

    def build_groups(gains)
      gains.reject { |classification, _| classification.exempt? }
           .group_by { |classification, _| [ classification.bucket, classification.term, classification.rate, classification.exemption_eligible ] }
           .map do |(bucket, term, rate, eligible), rows|
        Group.new(bucket: bucket, term: term, rate: rate, exemption_eligible: eligible, net: rows.sum { |_, amount| amount })
      end
    end

    def effective_rate(group)
      group.rate || @slab_rate
    end

    def loss_pool(groups)
      -groups.select { |g| g.net.negative? }.sum(&:net)
    end

    def positives(groups)
      groups.select { |g| g.net.positive? }.sort_by { |g| -effective_rate(g) }
    end

    # Reduces the groups (highest rate first) by `pool`. Returns the part of the pool that was not used.
    def absorb(pool, groups)
      groups.each do |group|
        break if pool <= 0

        used = [ pool, group.net ].min
        group.net -= used
        pool -= used
      end

      pool
    end
end
