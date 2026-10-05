# frozen_string_literal: true

module EventDestinations
  class CustomerUsageSerializer < ModelSerializer
    def serialize
      {
        from_datetime: iso8601(model.from_datetime),
        to_datetime: iso8601(model.to_datetime),
        issuing_date: iso8601(model.issuing_date),
        currency: model.currency,
        amount_cents: model.amount_cents,
        wallets: wallets_usage,
        charges_usage: charges_usage
      }
    end

    private

    def iso8601(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end

    def wallets
      options[:wallets] || []
    end

    # The ongoing usage each wallet absorbs, as the wallet refresh allocated it: wallet targets,
    # allowed fee types, thresholds and the cascade are all already applied. Customer scoped, so a
    # customer with several subscriptions sees the same totals on each of their records.
    def wallets_usage
      wallets.map do |wallet|
        {
          lago_id: wallet.id,
          credits: wallet.credits_ongoing_usage_balance.to_s,
          amount_cents: wallet.ongoing_usage_balance_cents,
          amount_currency: wallet.balance_currency
        }
      end
    end

    def wallet_amounts
      options[:wallet_amounts] || {}
    end

    # A plan carries a charge per feature, so a customer using a handful of them would otherwise
    # ship a long tail of zeroes on every record. Dropping them keeps headroom under the 1MB cap.
    # Fee#non_zero? is the trim daily usage already applies, so both payloads agree on what counts.
    #
    # One entry per charge and wallet: the charge's usage is split in proportion to what each wallet
    # absorbed for its billable metric, and the entries add up exactly to the charge totals.
    def charges_usage
      usage_fees = model.fees.select(&:non_zero?)
      metric_amounts = usage_fees.group_by { it.charge.billable_metric_id }.transform_values { |fees| fees.sum(&:amount_cents) }

      usage_fees.group_by(&:charge_id).flat_map do |_charge_id, fees|
        fee = fees.first
        units = fees.sum { BigDecimal(it.units) }
        events_count = fees.sum { it.events_count.to_i }
        amount_cents = fees.sum(&:amount_cents)
        weights = wallet_weights(fee.charge.billable_metric_id, metric_amounts[fee.charge.billable_metric_id])

        weights.keys.zip(
          split_units(units, weights.values),
          split_integer(events_count, weights.values),
          split_integer(amount_cents, weights.values)
        ).map do |wallet_id, wallet_units, wallet_events_count, wallet_amount_cents|
          {
            units: wallet_units.to_s,
            events_count: wallet_events_count,
            amount_cents: wallet_amount_cents,
            amount_currency: fee.amount_currency,
            charge: {
              lago_id: fee.charge_id,
              code: fee.charge.code
            },
            billable_metric: {
              lago_id: fee.charge.billable_metric_id,
              code: fee.charge.billable_metric.code
            },
            wallet_id:
          }
        end
      end
    end

    # The money each wallet absorbed for the billable metric, largest first. Wallets are recorded per
    # billable metric, so they are weighed against the metric's amount across all its charges. What
    # no wallet absorbed goes to a nil wallet, and so does the whole charge when no wallet did.
    def wallet_weights(billable_metric_id, amount_cents)
      weights = wallet_amounts.fetch(billable_metric_id, {})
        .select { |_wallet_id, cents| cents.positive? }
        .sort_by { |wallet_id, cents| [-cents, wallet_id] }
        .to_h
      unattributed = amount_cents - weights.values.sum

      if unattributed.positive?
        weights.merge(nil => unattributed)
      elsif weights.empty?
        {nil => 1}
      else
        weights
      end
    end

    # Largest remainder, so the parts add up to the total.
    def split_integer(total, weights)
      sum = weights.sum
      parts = weights.map { (total * it).div(sum) }
      order = weights.each_index.sort_by { |index| [-((total * weights[index]) % sum), index] }
      (total - parts.sum).times { parts[order[it]] += 1 }
      parts
    end

    # Split like the integers, at the precision of the total, so no part can go negative.
    def split_units(units, weights)
      factor = 10**units.scale

      split_integer((units * factor).to_i, weights).map { BigDecimal(it) / factor }
    end
  end
end
