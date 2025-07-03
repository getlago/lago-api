# frozen_string_literal: true

module V1
  module Customers
    class ChargeUsageSerializer < ModelSerializer
      def serialize
        model.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first
          usage_data = calculate_usage_data(fees)

          {
            **usage_data,
            charge: charge_data(fee),
            billable_metric: billable_metric_data(fee),
            filters: filters(fees),
            grouped_usage: grouped_usage(fees)
          }
        end
      end

      private

      def calculate_usage_data(fees)
        usage_calculator = ::Customers::FeesUsageCalculationService.new(fees)
        {
          units: usage_calculator.current_units.to_s,
          projected_units: usage_calculator.projected_units.to_s,
          events_count: fees.sum(&:events_count),
          amount_cents: usage_calculator.current_amount_cents,
          projected_amount_cents: usage_calculator.projected_amount_cents.to_i,
          amount_currency: fees.first.amount_currency
        }
      end

      def charge_data(fee)
        {
          lago_id: fee.charge_id,
          charge_model: fee.charge.charge_model,
          invoice_display_name: fee.charge.invoice_display_name
        }
      end

      def billable_metric_data(fee)
        metric = fee.billable_metric
        {
          lago_id: metric.id,
          name: metric.name,
          code: metric.code,
          aggregation_type: metric.aggregation_type
        }
      end

      def filters(fees)
        return [] unless fees.first.charge&.filters&.any?

        fees.group_by { |f| f.charge_filter&.id }
          .values
          .filter_map { |grouped_fees| build_filter_data(grouped_fees) }
      end

      def build_filter_data(grouped_fees)
        charge_filter = grouped_fees.first.charge_filter
        return nil unless charge_filter

        usage_data = calculate_usage_data(grouped_fees)

        {
          **usage_data.except(:amount_currency),
          invoice_display_name: charge_filter.invoice_display_name,
          values: charge_filter.to_h
        }
      end

      def grouped_usage(fees)
        return [] unless fees.any? { |f| f.grouped_by.present? }

        fees.group_by(&:grouped_by)
          .values
          .map { |grouped_fees| build_grouped_usage_data(grouped_fees) }
      end

      def build_grouped_usage_data(grouped_fees)
        usage_data = calculate_usage_data(grouped_fees)

        {
          **usage_data.except(:amount_currency),
          grouped_by: grouped_fees.first.grouped_by,
          filters: filters(grouped_fees)
        }
      end
    end
  end
end
