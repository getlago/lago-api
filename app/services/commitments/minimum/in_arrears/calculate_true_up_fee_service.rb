# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class CalculateTrueUpFeeService < Commitments::Minimum::CalculateTrueUpFeeService
        private

        def fees_total_amount_cents
          period_invoice_ids_result = helper_service.period_invoice_ids

          charge_fees = Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              invoice_id: period_invoice_ids_result.period_invoice_ids,
              charge: { pay_in_advance: false },
            )

          subscription_fees = Fee
            .subscription_kind
            .joins(subscription: :plan)
            .where(
              subscription_id: subscription.id,
              invoice_id: period_invoice_ids_result.period_invoice_ids,
              plan: { pay_in_advance: false },
            )

          dates_service = helper_service.dates_service
          charge_in_advance_fees = Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              charge: { pay_in_advance: true },
            )
            .where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )

          charge_fees.sum(:amount_cents) +
            subscription_fees.sum(:amount_cents) +
            charge_in_advance_fees.sum(:amount_cents)
        end
      end
    end
  end
end
