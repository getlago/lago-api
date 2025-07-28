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
        charge_has_filters = fees.first.charge&.filters&.any?
        charge_has_grouping = fees.any? { |f| f.grouped_by.present? }
        is_past_usage = root_name == "past_usage"

        current_units = fees.sum { |f| BigDecimal(f.units) }
        current_amount_cents = fees.sum(&:amount_cents)
        events_count = fees.sum { |f| f.events_count.to_i }

        projected_units = BigDecimal("0")
        projected_amount_cents = 0
        projected_pricing_unit_amount_cents = 0

        unless is_past_usage
          if charge_has_filters
            fees_with_defined_filters = fees.select(&:charge_filter_id)

            fees_with_defined_filters.each do |fee|
              result = ::Fees::ProjectionService.call(fees: [fee]).raise_if_error!
              projected_units += result.projected_units
              projected_amount_cents += result.projected_amount_cents
              projected_pricing_unit_amount_cents += result.projected_pricing_unit_amount_cents.to_i
            end
          elsif charge_has_grouping
            grouped_fees = fees.group_by(&:grouped_by).values

            grouped_fees.each do |group_fee_list|
              result = ::Fees::ProjectionService.call(fees: group_fee_list).raise_if_error!
              projected_units += result.projected_units
              projected_amount_cents += result.projected_amount_cents
              projected_pricing_unit_amount_cents += result.projected_pricing_unit_amount_cents.to_i
            end
          else
            result = ::Fees::ProjectionService.call(fees: fees).raise_if_error!
            projected_units = result.projected_units
            projected_amount_cents = result.projected_amount_cents
            projected_pricing_unit_amount_cents = result.projected_pricing_unit_amount_cents.to_i
          end
        end

        pricing_details = fees.first.pricing_unit_usage&.then do |pricing_unit|
          {
            amount_cents: fees.map(&:pricing_unit_usage).compact.sum(&:amount_cents),
            projected_amount_cents: projected_pricing_unit_amount_cents.to_i,
            short_name: pricing_unit.short_name,
            conversion_rate: pricing_unit.conversion_rate
          }
        end

        {
          units: current_units.to_s,
          events_count: events_count,
          amount_cents: current_amount_cents,
          amount_currency: fees.first.amount_currency,
          projected_units: projected_units.to_s,
          projected_amount_cents: projected_amount_cents.to_i,
          pricing_unit_details: pricing_details
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
        usage_data = calculate_usage_data(grouped_fees)

        {
          **usage_data.except(:amount_currency),
          invoice_display_name: charge_filter&.invoice_display_name,
          values: charge_filter&.to_h
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
