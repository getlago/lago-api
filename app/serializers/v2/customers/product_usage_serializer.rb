# frozen_string_literal: true

module V2
  module Customers
    class ProductUsageSerializer < V1::Customers::ChargeUsageSerializer
      def serialize
        model.group_by { |fee| [fee.invoiceable_id, fee.rate_card_rate_id, fee.rate_override_id] }.values.map do |fees|
          fee = fees.first
          product = fee.invoiceable
          rate = fee.rate_override || fee.rate_card_rate

          {
            **calculate_usage_data(fees),
            product: {lago_id: product.id, name: product.name, code: product.code},
            rate_card: {lago_id: fee.rate_card_rate&.rate_card_id, code: fee.rate_card_rate&.rate_card&.code},
            rate: {lago_id: rate.id, rate_model: rate.rate_model},
            billable_metric: billable_metric_data(fee),
            filters: filters(fees),
            grouped_usage: grouped_usage(fees)
          }
        end
      end

      private

      def filters(fees)
        if fees.first.invoiceable.filters.any?
          fees.group_by(&:product_filter_id).values.map { |grouped_fees| build_filter_data(grouped_fees) }
        else
          []
        end
      end

      def build_filter_data(grouped_fees)
        filter = grouped_fees.first.product_filter

        {
          **calculate_usage_data(grouped_fees).except(:amount_currency),
          lago_id: filter&.id,
          code: filter&.code,
          invoice_display_name: filter&.invoice_display_name,
          values: filter&.to_h
        }
      end
    end
  end
end
