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

    def charges_usage
      model.fees.group_by(&:charge_id).map do |_charge_id, fees|
        fee = fees.first

        {
          units: fees.sum { BigDecimal(it.units) }.to_s,
          events_count: fees.sum { it.events_count.to_i },
          amount_cents: fees.sum(&:amount_cents),
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
