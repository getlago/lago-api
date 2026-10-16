# frozen_string_literal: true

module V1
  module Customers
    class ProjectedUsageSerializer < ModelSerializer
      def serialize
        payload = {
          from_datetime: model.from_datetime,
          to_datetime: model.to_datetime,
          issuing_date: model.issuing_date,
          currency: model.currency,
          amount_cents: model.amount_cents,
          projected_amount_cents: projected_amount_cents,
          total_amount_cents: model.total_amount_cents,
          taxes_amount_cents: model.taxes_amount_cents,
          lago_invoice_id: nil
        }

        payload.merge!(charges_usage)
        payload
      end

      def projected_amount_cents
        model.projections.for(model.fees).amount_cents
      end

      private

      def charges_usage
        {
          charges_usage: ::V1::Customers::ProjectedChargeUsageSerializer.new(
            model.fees,
            projections: model.projections
          ).serialize
        }
      end
    end
  end
end
