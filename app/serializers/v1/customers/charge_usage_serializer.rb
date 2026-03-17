# frozen_string_literal: true

module V1
  module Customers
    class ChargeUsageSerializer < ModelSerializer
      def serialize
        model.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first
          charge = fee.charge
          usage_data = calculate_usage_data(fees)

          payload = {
            **usage_data,
            charge: charge_data(fee),
            billable_metric: billable_metric_data(fee),
            filters: filters(fees),
            grouped_usage: grouped_usage(fees, charge)
          }

          if charge.presentation_group_keys.present? && charge.pricing_group_keys.blank?
            payload[:presentation_breakdown] = presentation_breakdown(fees, charge)
          end

          payload
        end
      end

      private

      def calculate_usage_data(fees)
        {
          **current_usage_data(fees),
          pricing_unit_details: pricing_unit_details(fees)
        }
      end

      def current_usage_data(fees)
        {
          units: current_units(fees).to_s,
          total_aggregated_units: total_aggregated_units(fees).to_s,
          events_count: fees.sum { |f| f.events_count.to_i },
          amount_cents: fees.sum(&:amount_cents),
          amount_currency: fees.first.amount_currency
        }
      end

      def current_units(fees)
        fees.sum { |f| BigDecimal(f.units) }
      end

      def total_aggregated_units(fees)
        fees.sum { |f| BigDecimal(f.total_aggregated_units || 0) }
      end

      def past_usage?
        root_name == "past_usage"
      end

      def pricing_unit_details(fees)
        fees.first.pricing_unit_usage&.then do |pricing_unit|
          {
            amount_cents: fees.map(&:pricing_unit_usage).compact.sum(&:amount_cents),
            short_name: pricing_unit.short_name,
            conversion_rate: pricing_unit.conversion_rate
          }
        end
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

      def grouped_usage(fees, charge = nil)
        return [] unless fees.any? { |f| f.grouped_by.present? }

        fees.group_by(&:grouped_by)
          .values
          .map { |grouped_fees| build_grouped_usage_data(grouped_fees, charge) }
      end

      def build_grouped_usage_data(grouped_fees, charge = nil)
        usage_data = calculate_usage_data(grouped_fees)

        payload = {
          **usage_data.except(:amount_currency),
          grouped_by: grouped_fees.first.grouped_by,
          filters: filters(grouped_fees)
        }

        if charge&.presentation_group_keys&.present?
          payload[:presentation_breakdown] = presentation_breakdown(grouped_fees, charge)
        end

        payload
      end

      def presentation_breakdown(fees, charge)
        presentation_keys = charge.presentation_group_keys
        return [] if presentation_keys.blank?

        fee = fees.first
        from_datetime = fee.properties["charges_from_datetime"]
        to_datetime = fee.properties["charges_to_datetime"]

        scope = EnrichedEvent
          .where(organization_id: charge.organization_id)
          .where(charge_id: charge.id)
          .where(subscription_id: fee.subscription_id)

        scope = scope.where("timestamp >= ?", from_datetime) if from_datetime
        scope = scope.where("timestamp <= ?", to_datetime) if to_datetime

        # Filter by pricing grouped_by values if present
        grouped_by = fee.grouped_by
        if grouped_by.present?
          grouped_by.each do |key, value|
            scope = scope.where("grouped_by ->> ? = ?", key, value)
          end
        end

        events = scope.joins(:event).select(
          "events.properties",
          "enriched_events.decimal_value"
        )

        # Group by presentation key values and sum decimal_value
        breakdown = Hash.new { |h, k| h[k] = BigDecimal("0") }
        events.each do |event|
          presentation_by = presentation_keys.each_with_object({}) do |key, hash|
            hash[key] = event.properties&.dig(key).to_s
          end
          breakdown[presentation_by] += event.decimal_value
        end

        breakdown.map do |presentation_by, units|
          {presentation_by:, units: units.to_s}
        end
      end
    end
  end
end
