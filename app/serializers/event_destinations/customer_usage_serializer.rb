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

    # A plan carries a charge per feature, so a customer using a handful of them would otherwise
    # ship a long tail of zeroes on every record. Dropping them keeps headroom under the 1MB cap.
    def charges_usage
      model.fees.group_by(&:charge_id).filter_map do |_charge_id, fees|
        units = fees.sum { BigDecimal(it.units) }
        amount_cents = fees.sum(&:amount_cents)
        events_count = fees.sum { it.events_count.to_i }

        # Events with nothing to show for them are still usage: a sum over values that cancel out
        # leaves units and amount at zero while events did happen, and the fee is kept deliberately.
        next if units.zero? && amount_cents.zero? && events_count.zero?

        fee = fees.first

        {
          units: units.to_s,
          events_count: events_count,
          amount_cents: amount_cents,
          amount_currency: fee.amount_currency,
          charge: {
            lago_id: fee.charge_id,
            code: fee.charge.code
          },
          billable_metric: {
            lago_id: fee.charge.billable_metric_id,
            code: fee.charge.billable_metric.code
          }
        }
      end
    end
  end
end
