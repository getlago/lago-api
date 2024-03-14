# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class CalculateTrueUpFeeService < Commitments::Minimum::CalculateTrueUpFeeService
        private

        def subscription_fees
          invoices_result = FetchInvoicesService.call(commitment: minimum_commitment, invoice_subscription:)

          Fee
            .subscription_kind
            .joins(subscription: :plan)
            .where(
              subscription_id: subscription.id,
              invoice_id: invoices_result.invoices.ids,
              plan: { pay_in_advance: false },
            )
        end

        def charge_fees
          dates_service = Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription:,
          ).call

          Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              charge: { pay_in_advance: false },
            )
            .where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )
        end

        def charge_in_advance_fees
          dates_service = Commitments::DatesService.new_instance(
            commitment: minimum_commitment,
            invoice_subscription:,
          ).call

          Fee
            .charge_kind
            .joins(:charge)
            .where(
              subscription_id: subscription.id,
              charge: { pay_in_advance: true },
              pay_in_advance: true,
            )
            .where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )
        end

        def charge_in_advance_recurring_fees
          if !invoice_subscription.previous_invoice_subscription &&
             (!subscription.plan.yearly? || !subscription.plan.bill_charges_monthly?)
            return Fee.none
          end

          is = if subscription.plan.yearly? && subscription.plan.bill_charges_monthly?
            invoice_subscription
          else
            invoice_subscription.previous_invoice_subscription
          end

          dates_service = Commitments::Minimum::InArrears::DatesService.new(
            commitment: minimum_commitment,
            invoice_subscription: is,
          ).call

          scope = Fee
            .charge_kind
            .joins(:charge)
            .joins(charge: :billable_metric)
            .where(billable_metric: { recurring: true })
            .where(
              subscription_id: subscription.id,
              charge: { pay_in_advance: true },
              pay_in_advance: false,
            )
            .where(
              "(fees.properties->>'charges_to_datetime') <= ?",
              dates_service.end_of_period&.iso8601(3),
            )

          # rubocop:disable Style/ConditionalAssignment
          if subscription.plan.yearly? && subscription.plan.bill_charges_monthly?
            scope = scope
              .where(
                "(fees.properties->>'charges_from_datetime') >= ?",
                dates_service.previous_beginning_of_period - 1.month,
              )
              .where.not(invoice_id: invoice_subscription.invoice_id)
          else
            scope = scope.where(
              "(fees.properties->>'charges_from_datetime') >= ?",
              dates_service.previous_beginning_of_period,
            )
          end
          # rubocop:enable Style/ConditionalAssignment

          scope
        end
      end
    end
  end
end
