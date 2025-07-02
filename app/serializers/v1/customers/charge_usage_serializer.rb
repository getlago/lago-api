# frozen_string_literal: true

module V1
  module Customers
    class ChargeUsageSerializer < ModelSerializer
      def serialize
        model.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first
          ratio = calculate_time_ratio(fee)
          usage_data = calculate_usage_data(fees, ratio)

          {
            **usage_data,
            charge: charge_data(fee),
            billable_metric: billable_metric_data(fee),
            filters: filters(fees, ratio),
            grouped_usage: grouped_usage(fees, ratio)
          }
        end
      end

      private

      def calculate_time_ratio(fee)
        from_date = fee.properties["from_datetime"].to_date
        to_date = fee.properties["to_datetime"].to_date
        current_date = Date.current

        total_days = (to_date - from_date).to_i + 1

        charges_duration = fee.properties["charges_duration"] || total_days

        return 1.0 if current_date >= to_date
        return 0.0 if current_date < from_date

        days_passed = (current_date - from_date).to_i + 1

        ratio = days_passed.to_f / charges_duration
        ratio.clamp(0.0, 1.0)
      end

      def calculate_usage_data(fees, ratio)
        current_units = sum_units(fees)
        current_amount_cents = fees.sum(&:amount_cents)

        if fees.first.charge.billable_metric.recurring?
          projected_units = current_units
          projected_amount_cents = current_amount_cents
        else
          projected_units = ratio > 0 ? (current_units / BigDecimal(ratio.to_s)).round(2) : BigDecimal('0')
          projected_amount_cents = ratio > 0 ? (current_amount_cents / BigDecimal(ratio.to_s)).round.to_i : 0
        end

        {
          units: current_units.to_s,
          projected_units: projected_units.to_s,
          events_count: fees.sum(&:events_count),
          amount_cents: current_amount_cents,
          projected_amount_cents: projected_amount_cents.to_i,
          amount_currency: fees.first.amount_currency
        }
      end

      def sum_units(fees)
        fees.sum { |f| BigDecimal(f.units) }
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

      def filters(fees, ratio)
        return [] unless fees.first.charge&.filters&.any?

        fees.group_by { |f| f.charge_filter&.id }
            .values
            .filter_map { |grouped_fees| build_filter_data(grouped_fees, ratio) }
      end

      def build_filter_data(grouped_fees, ratio)
        charge_filter = grouped_fees.first.charge_filter
        return nil unless charge_filter

        usage_data = calculate_usage_data(grouped_fees, ratio)

        {
          **usage_data.except(:amount_currency),
          invoice_display_name: charge_filter.invoice_display_name,
          values: charge_filter.to_h
        }
      end

      def grouped_usage(fees, ratio)
        return [] unless fees.any? { |f| f.grouped_by.present? }

        fees.group_by(&:grouped_by)
            .values
            .map { |grouped_fees| build_grouped_usage_data(grouped_fees, ratio) }
      end

      def build_grouped_usage_data(grouped_fees, ratio)
        usage_data = calculate_usage_data(grouped_fees, ratio)

        {
          **usage_data.except(:amount_currency),
          grouped_by: grouped_fees.first.grouped_by,
          filters: filters(grouped_fees, ratio)
        }
      end
    end
  end
end