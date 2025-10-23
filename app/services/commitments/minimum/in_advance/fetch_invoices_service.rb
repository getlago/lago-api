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
            current_usage: true
          )

          return ds unless subscription.terminated?

          Subscriptions::TerminatedDatesService.new(
            subscription:,
            invoice: invoice_subscription.invoice,
            date_service: ds
          ).call
        end

        def fetch_invoices
          unless plan.charges_or_fixed_charges_billed_in_monthly_split_intervals?
            return Invoice.where(id: invoice_subscription.invoice_id)
          end

          previous_invoice_subscription = invoice_subscription.previous_invoice_subscription

          return Invoice.where(id: invoice_subscription.invoice_id) unless previous_invoice_subscription

          ds = Subscriptions::DatesService.new_instance(
            subscription,
            previous_invoice_subscription.timestamp,
            current_usage: true
          )

          # note: current solution solves the problem for billed monthly charges and fixed charges. However, 
          # we still have wrong calculation when we're issuing an invoice for the previous period, but it contains
          # pay_in_advance fixed charges and charges (recurring, for example), because in invoice_subscription
          # we'll have boundaries of previous billing period.
          invoice_ids_query = subscription
            .invoice_subscriptions
            .where(
              "(GREATEST(charges_from_datetime, fixed_charges_from_datetime) >= ? " \
              "AND GREATEST(charges_to_datetime, fixed_charges_to_datetime) <= ?)",
              ds.previous_beginning_of_period,
              ds.end_of_period
            ).select(:invoice_id)

          Invoice.where(id: invoice_ids_query)
        end
      end
    end
  end
end
