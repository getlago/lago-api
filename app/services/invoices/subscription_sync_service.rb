# frozen_string_literal: true

module Invoices
  class SubscriptionSyncService < SubscriptionService
    def create
      active_subscriptions = subscriptions.select(&:active?)
      return result if active_subscriptions.empty? && recurring

      result = nil
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          organization: customer.organization,
          customer:,
          issuing_date:,
          payment_due_date:,
          net_payment_term: customer.applicable_net_payment_term,
          invoice_type: :subscription,
          currency:,
          timezone: customer.applicable_timezone,
          status: invoice_status,
        )

        result = Invoices::CalculateFeesService.new(
          invoice:,
          subscriptions: recurring ? active_subscriptions : subscriptions,
          timestamp:,
          recurring:,
        ).call

        result.raise_if_error!
      end

      if grace_period?
        SendWebhookJob.perform_later('invoice.drafted', invoice) if should_deliver_webhook?
      else
        SendWebhookJob.perform_later('invoice.created', invoice) if should_deliver_webhook?
        InvoiceMailer.with(invoice:).finalized.deliver_later if should_deliver_finalized_email?
        Invoices::Payments::CreateSyncService.new(invoice).call
        track_invoice_created(invoice)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end