# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class FetchInvoicesService < Commitments::FetchInvoicesService
        private

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

        def fetch_invoices
          plan = subscription.plan

          if !subscription.plan.yearly? || !plan.bill_charges_monthly?
            return Invoice.where(id: invoice_subscription.invoice_id)
          end

          previous_invoice_subscription = invoice_subscription.previous_invoice_subscription

          return Invoice.where(id: invoice_subscription.invoice_id) unless previous_invoice_subscription

          ds = Subscriptions::DatesService.new_instance(
            subscription,
            previous_invoice_subscription.timestamp,
            current_usage: true,
          )

          invoice_ids = subscription
            .invoice_subscriptions
            .where(
              'charges_from_datetime >= ? AND charges_to_datetime <= ?',
              ds.previous_beginning_of_period,
              ds.end_of_period,
            ).pluck(:invoice_id)

          Invoice.where(id: invoice_ids)
        end
      end
    end
  end
end
