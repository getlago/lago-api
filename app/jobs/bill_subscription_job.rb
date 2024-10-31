# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError

  def perform(subscriptions, timestamp, invoicing_reason:, invoice: nil, skip_charges: false)
    result = Invoices::SubscriptionService.call(
      subscriptions:,
      timestamp:,
      invoicing_reason:,
      invoice:,
      skip_charges:
    )
    return if result.success?
    # NOTE: We don't want a dead job for failed invoice due to the tax reason.
    #       This invoice should be in failed status and can be retried.
    return if tax_error?(result)

    # If the invoice was passed as an argument, it means the job was already retried (see end of function)
    if invoice || !result.invoice&.generating?
      InvoiceError.create_for(invoice: result.invoice, error: result.error)
      return result.raise_if_error!
    end

    # On billing day, we'll retry the job further in the future because the system is typically under heavy load
    is_billing_date = invoicing_reason.to_sym == :subscription_periodic

    self.class.set(wait: is_billing_date ? 5.minutes : 3.seconds).perform_later(
      subscriptions,
      timestamp,
      invoicing_reason:,
      invoice: result.invoice,
      skip_charges:
    )
  end

  private

  def tax_error?(result)
    return false unless result.error.is_a?(BaseService::ValidationFailure)

    result.error&.messages&.dig(:tax_error)&.present?
  end
end
