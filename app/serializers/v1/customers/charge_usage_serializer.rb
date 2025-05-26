# frozen_string_literal: true

module V1
  module Customers
    class ChargeUsageSerializer < ModelSerializer
      def serialize
        model.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first

          {
            units: fees.map { |f| BigDecimal(f.units) }.sum.to_s,
            events_count: fees.sum(0) { |f| f.events_count.to_i },
            amount_cents: fees.sum(&:amount_cents),
            amount_currency: fee.amount_currency,
            charge: {
              lago_id: charge_id,
              charge_model: fee.charge.charge_model,
              invoice_display_name: fee.charge.invoice_display_name
            },
            billable_metric: {
              lago_id: fee.billable_metric.id,
              name: fee.billable_metric.name,
              code: fee.billable_metric.code,
              aggregation_type: fee.billable_metric.aggregation_type
            },
            filters: filters(fees),
            grouped_usage: grouped_usage(fees)
          }
        end
      end

      private

      def filters(fees)
        return [] unless fees.first.charge&.filters&.any?

        fees.group_by { |f| f.charge_filter&.to_h }.values.map do |grouped_fees|
          {
            units: grouped_fees.map { |f| BigDecimal(f.units) }.sum.to_s,
            amount_cents: grouped_fees.sum(&:amount_cents),
            events_count: grouped_fees.sum(&:events_count),
            invoice_display_name: grouped_fees.first.charge_filter&.invoice_display_name,
            values: grouped_fees.first.charge_filter&.to_h
          }
        end.compact
      end

      def grouped_usage(fees)
        return [] unless fees.any? { |f| f.grouped_by.present? }

        fees.group_by(&:grouped_by).values.map do |grouped_fees|
          {
            amount_cents: grouped_fees.sum(&:amount_cents),
            events_count: grouped_fees.sum(&:events_count),
            units: grouped_fees.map { |f| BigDecimal(f.units) }.sum.to_s,
            grouped_by: grouped_fees.first.grouped_by,
            filters: filters(grouped_fees)
          }
        end
      end
    end
  end
end
