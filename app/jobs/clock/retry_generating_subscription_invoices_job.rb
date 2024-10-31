# frozen_string_literal: true

module Clock
  class RetryGeneratingSubscriptionInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'

    THRESHOLD = -> { 1.day.ago }

    def perform
      Invoice.subscription.generating.where.not(id: InvoiceError.select(:id)).where('created_at < ?', THRESHOLD.call).find_each do |invoice|
        next unless invoice.invoice_subscriptions.any?
        invoicing_reasons = invoice.invoice_subscriptions.pluck(:invoicing_reason).uniq.compact
        invoicing_reason = (invoicing_reasons.size == 1) ? invoicing_reasons.first : :upgrading
        BillSubscriptionJob.perform_later(
          invoice.subscriptions.to_a,
          invoice.invoice_subscriptions.first.timestamp.to_i,
          invoicing_reason:,
          invoice:,
          skip_charges: invoice.skip_charges
        )
      end
    end
  end
end
