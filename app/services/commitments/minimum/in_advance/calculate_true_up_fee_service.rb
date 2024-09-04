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

        def precise_amount_cents
          return 0.to_d unless invoice_subscription.previous_invoice_subscription

          super
        end

        def subscription_fees
          dates_service = Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription: invoice_subscription.previous_invoice_subscription
          ).call

          Fee
            .subscription_kind
            .joins(subscription: :plan)
            .where(
              "(fees.properties->>'from_datetime') >= ?",
              dates_service.previous_beginning_of_period
            )
            .where(
              "(fees.properties->>'to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3)
            )
            .where(
              subscription_id: subscription.id,
              plan: {pay_in_advance: true}
            )
        end

        def charge_fees
          invoices_result = FetchInvoicesService.call(commitment: minimum_commitment, invoice_subscription:)

          Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              invoice_id: invoices_result.invoices.ids,
              charge: {pay_in_advance: false}
            )
        end

        def charge_in_advance_fees
          dates_service = Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription: invoice_subscription.previous_invoice_subscription
          ).call

          Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              charge: {pay_in_advance: true},
              pay_in_advance: true
            )
            .where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3)
            )
        end

        def charge_in_advance_recurring_fees
          return Fee.none unless invoice_subscription.previous_invoice_subscription

          dates_service = Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription: invoice_subscription.previous_invoice_subscription
          ).call

          Fee
            .charge_kind
            .joins(:charge)
            .joins(charge: :billable_metric)
            .where(billable_metric: {recurring: true})
            .where(
              subscription_id: subscription.id,
              charge: {pay_in_advance: true},
              pay_in_advance: false
            )
            .where(
              "(fees.properties->>'from_datetime') >= ?",
              dates_service.previous_beginning_of_period
            )
            .where(
              "(fees.properties->>'to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3)
            )
        end
      end
    end
  end
end
