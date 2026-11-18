# frozen_string_literal: true

module V1
  module DailyUsages
    # A contract rate card's usage on its window, in the shape of a subscription's daily usage
    # so that both parse alike: its one charges_usage entry names a rate card and a product
    # where a subscription's names a charge.
    class RateCardUsageSerializer < ModelSerializer
      def serialize
        {
          from_datetime: billing_segment.started_at,
          to_datetime: billing_segment.ended_at,
          issuing_date: billing_segment.billing_at.in_time_zone(customer.applicable_timezone).to_date.iso8601,
          currency: billing_segment.currency,
          amount_cents: model.amount_cents,
          total_amount_cents: model.amount_cents + model.taxes_amount_cents,
          taxes_amount_cents: model.taxes_amount_cents,
          lago_invoice_id: nil,
          charges_usage: [charge_usage]
        }
      end

      private

      delegate :billing_segment, :contract_rate_card, to: :model
      delegate :customer, to: :billing_segment
      delegate :rate_card, to: :contract_rate_card
      delegate :product, :product_filter, to: :rate_card

      def charge_usage
        {
          **usage_data(model.fees),
          amount_currency: billing_segment.currency,
          contract_rate_card: {lago_id: contract_rate_card.id},
          rate_card: {
            lago_id: rate_card.id,
            code: rate_card.code,
            rate_model: billing_segment.rate.rate_model
          },
          product: {lago_id: product.id, code: product.code},
          product_filter: product_filter_data,
          billable_metric: {
            lago_id: billable_metric.id,
            name: billable_metric.name,
            code: billable_metric.code,
            aggregation_type: billable_metric.aggregation_type
          },
          # A card prices a single filter of its product, named above, so it has no filter breakdown.
          filters: [],
          grouped_usage:
        }
      end

      # Values in the shape of a subscription's filters[].values: {key => [values]}.
      def product_filter_data
        return unless product_filter

        {lago_id: product_filter.id, code: product_filter.code, values: product_filter.to_h}
      end

      def grouped_usage
        return [] unless model.fees.any? { |fee| fee.grouped_by.present? }

        model.fees.group_by(&:grouped_by).map do |grouped_by, fees|
          {**usage_data(fees), grouped_by:, filters: []}
        end
      end

      def usage_data(fees)
        {
          units: fees.sum { |fee| BigDecimal(fee.units) }.to_s,
          total_aggregated_units: fees.sum { |fee| BigDecimal(fee.total_aggregated_units || 0) }.to_s,
          events_count: fees.sum { |fee| fee.events_count.to_i },
          amount_cents: fees.sum(&:amount_cents),
          pricing_unit_details: pricing_unit_details(fees)
        }
      end

      def pricing_unit_details(fees)
        fees.first.pricing_unit_usage&.then do |pricing_unit_usage|
          {
            amount_cents: fees.filter_map(&:pricing_unit_usage).sum(&:amount_cents),
            short_name: pricing_unit_usage.short_name,
            conversion_rate: pricing_unit_usage.conversion_rate
          }
        end
      end

      def billable_metric
        product.billable_metric
      end
    end
  end
end
