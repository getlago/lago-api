# frozen_string_literal: true

module V1
  module Customers
    class PastUsageSerializer < ModelSerializer
      def serialize
        payload = {
          from_datetime: invoice_subscription.from_datetime.iso8601,
          to_datetime: invoice_subscription.to_datetime.iso8601,
          issuing_date: invoice.issuing_date.iso8601,
          currency: invoice.currency,
          amount_cents: invoice.fees_amount_cents,
          total_amount_cents: invoice.fees_amount_cents + taxes_amount_cents,
          taxes_amount_cents:,
          invoice_id: invoice.id,
        }

        payload.merge!(charges_usage) if include?(:charges_usage)
        payload
      end

      private

      delegate :invoice_subscription, :fees, to: :model
      delegate :invoice, to: :invoice_subscription

      def taxes_amount_cents
        @taxes_amount_cents ||= invoice.fees.sum(:taxes_amount_cents)
      end

      def charges_usage
        # TODO: do it in the query or in the charge serializer and share it with current usage
        usage = fees.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first

          OpenStruct.new(
            units: fees.sum(&:units),
            amount_cents: fees.sum(&:amount_cents),
            amount_currency: fee.amount_currency,
            charge: OpenStruct.new(
              id: charge_id,
              charge_model: fee.charge.charge_model,
            ),
            billable_metric: OpenStruct.new(
              id: fee.billable_metric.id,
              name: fee.billable_metric.name,
              code: fee.billable_metric.code,
              aggregation_type: fee.billable_metric.aggregation_type,
            ),
            groups: fees.sort_by { |f| f.group&.name }.map do |f|
              next unless f.group

              OpenStruct.new(
                id: f.group.id,
                key: f.group.parent&.value || f.group.key,
                value: f.group.value,
                units: f.units,
                amount_cents: f.amount_cents,
              )
            end.compact,
          )
        end

        ::CollectionSerializer.new(
          usage,
          ::V1::Customers::ChargeUsageSerializer,
          collection_name: 'charges_usage',
        ).serialize
      end
    end
  end
end
