# frozen_string_literal: true

module V1
  module Customers
    class ChargeUsageSerializer < ModelSerializer
      def serialize
        model.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first

          {
            units: fees.map { |f| BigDecimal(f.units) }.sum.to_s,
            amount_cents: fees.sum(&:amount_cents),
            amount_currency: fee.amount_currency,
            charge: {
              id: charge_id,
              charge_model: fee.charge.charge_model,
            },
            billable_metric: {
              id: fee.billable_metric.id,
              name: fee.billable_metric.name,
              code: fee.billable_metric.code,
              aggregation_type: fee.billable_metric.aggregation_type,
            },
            groups: groups(fees),
          }
        end
      end

      private

      def groups(fees)
        fees.sort_by { |f| f.group&.name }.map do |f|
          next unless f.group

          {
            lago_id: f.group.id,
            key: f.group.parent&.value || f.group.key,
            value: f.group.value,
            units: f.units,
            amount_cents: f.amount_cents,
          }
        end.compact
      end
    end
  end
end
