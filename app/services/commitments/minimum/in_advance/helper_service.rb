# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class HelperService < Commitments::HelperService
        def dates_service
          ds = Subscriptions::DatesService.new_instance(
            subscription,
            invoice_subscription.timestamp,
            current_usage: true,
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

          previous_invoice_subscription = invoice_subscription.previous_invoice_subscription

          return [invoice_subscription.invoice_id] unless previous_invoice_subscription

          ds = Subscriptions::DatesService.new_instance(
            subscription,
            previous_invoice_subscription.timestamp,
            current_usage: true,
          )

          subscription
            .invoice_subscriptions
            .where(
              'charges_from_datetime >= ? AND charges_to_datetime <= ?',
              ds.previous_beginning_of_period,
              ds.end_of_period,
            )
            .pluck(:invoice_id)
        end
      end
    end
  end
end
