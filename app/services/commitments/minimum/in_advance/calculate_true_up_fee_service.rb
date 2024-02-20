# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class CalculateTrueUpFeeService < Commitments::Minimum::CalculateTrueUpFeeService
        private

        def amount_cents
          return 0 unless invoice_subscription.previous_invoice_subscription

          super
        end

        def fees_total_amount_cents
          is = subscription.terminated? ? invoice_subscription : invoice_subscription.previous_invoice_subscription

          dates_service = Commitments::HelperService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription: is,
          ).dates_service

          subscription_fees = Fee
            .subscription_kind
            .joins(subscription: :plan)
            .where(
              "(fees.properties->>'from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
            .where(
              "(fees.properties->>'to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )
            .where(
              subscription_id: subscription.id,
              plan: { pay_in_advance: true },
            )

          charge_in_advance_fees = Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
            )
            .where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )

          subscription_fees.sum(:amount_cents) + charge_in_advance_fees.sum(:amount_cents)
        end
      end
    end
  end
end
