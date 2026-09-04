# frozen_string_literal: true

module EventDestinations
  class CustomerUsageSerializer < ModelSerializer
    def serialize
      {
        from_datetime: model.from_datetime,
        to_datetime: model.to_datetime,
        issuing_date: model.issuing_date,
        currency: model.currency,
        amount_cents: model.amount_cents,
        charges_usage: charges_usage
      }
    end

    private

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
