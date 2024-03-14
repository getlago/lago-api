# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class HelperService < Commitments::HelperService
        def dates_service
          ds = Subscriptions::DatesService.new_instance(
            subscription,
            invoice_subscription.timestamp,
            current_usage: subscription.terminated?,
          )

          return ds unless subscription.terminated?

          Subscriptions::TerminatedDatesService.new(
            subscription:,
            invoice: invoice_subscription.invoice,
            date_service: ds,
          ).call
        end

        private

        def fetch_period_invoice_ids
          plan = subscription.plan

          return [invoice_subscription.invoice_id] if !subscription.plan.yearly? || !plan.bill_charges_monthly?

          subscription
            .invoice_subscriptions
            .where(
              'from_datetime >= ? AND to_datetime <= ?',
              dates_service.previous_beginning_of_period,
              dates_service.end_of_period,
            )
            .pluck(:invoice_id)
        end
      end
    end
  end
end
