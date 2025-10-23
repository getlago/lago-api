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

          # This will be deleted in main, but when we add fixed_charges boundaries, it cannot be OR, becuase
          # then monthly fixed_charges inovice is also shown for the previous period (because charges boundaries will be the
          # previous yearly period)
          invoice_ids_query = subscription
            .invoice_subscriptions
            .where(
              "(charges_from_datetime >= ? AND charges_to_datetime <= ?)",
              ds.previous_beginning_of_period,
              ds.end_of_period
            ).select(:invoice_id)

          Invoice.where(id: invoice_ids_query)
        end
      end
    end
  end
end
