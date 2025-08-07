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
        {
          **current_usage_data(fees),
          **projected_usage_data(fees),
          pricing_unit_details: pricing_unit_details(fees)
        }
      end

      def current_usage_data(fees)
        {
          units: current_units(fees).to_s,
          events_count: fees.sum { |f| f.events_count.to_i },
          amount_cents: fees.sum(&:amount_cents),
          amount_currency: fees.first.amount_currency
        }
      end

      def current_units(fees)
        fees.sum { |f| BigDecimal(f.units) }
      end

      def projected_usage_data(fees)
        zero_projected_usage

        # return zero_projected_usage if past_usage?

        # projection = calculate_projection(fees)

        # {
        #   projected_units: projection[:units].to_s,
        #   projected_amount_cents: projection[:amount_cents].to_i
        # }
      end

      def zero_projected_usage
        {
          projected_units: "0.0",
          projected_amount_cents: 0
        }
      end

      def past_usage?
        root_name == "past_usage"
      end

      def calculate_projection(fees)
        if charge_has_filters?(fees)
          calculate_filtered_projection(fees)
        elsif charge_has_grouping?(fees)
          calculate_grouped_projection(fees)
        else
          calculate_simple_projection(fees)
        end
      end

      def charge_has_filters?(fees)
        fees.first.charge&.filters&.any?
      end

      def charge_has_grouping?(fees)
        fees.any? { |f| f.grouped_by.present? }
      end

      def calculate_filtered_projection(fees)
        fees_with_defined_filters = fees.select(&:charge_filter_id)

        fees_with_defined_filters.reduce(initial_projection_values) do |totals, fee|
          result = ::Fees::ProjectionService.call(fees: [fee]).raise_if_error!
          accumulate_projection(totals, result)
        end
      end

      def calculate_grouped_projection(fees)
        grouped_fees = fees.group_by(&:grouped_by).values

        grouped_fees.reduce(initial_projection_values) do |totals, group_fee_list|
          result = ::Fees::ProjectionService.call(fees: group_fee_list).raise_if_error!
          accumulate_projection(totals, result)
        end
      end

      def calculate_simple_projection(fees)
        result = ::Fees::ProjectionService.call(fees: fees).raise_if_error!

        {
          units: result.projected_units,
          amount_cents: result.projected_amount_cents,
          pricing_unit_amount_cents: result.projected_pricing_unit_amount_cents.to_i
        }
      end

      def initial_projection_values
        {
          units: BigDecimal("0.0"),
          amount_cents: 0,
          pricing_unit_amount_cents: 0
        }
      end

      def accumulate_projection(totals, result)
        {
          units: totals[:units] + result.projected_units,
          amount_cents: totals[:amount_cents] + result.projected_amount_cents,
          pricing_unit_amount_cents: totals[:pricing_unit_amount_cents] + result.projected_pricing_unit_amount_cents.to_i
        }
      end

      def pricing_unit_details(fees)
        fees.first.pricing_unit_usage&.then do |pricing_unit|
          {
            amount_cents: fees.map(&:pricing_unit_usage).compact.sum(&:amount_cents),
            projected_amount_cents: projected_pricing_unit_amount_cents(fees),
            short_name: pricing_unit.short_name,
            conversion_rate: pricing_unit.conversion_rate
          }
        end
      end

      def projected_pricing_unit_amount_cents(fees)
        0

        # return 0 if past_usage?

        # calculate_projection(fees)[:pricing_unit_amount_cents]
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
