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
    return if result.error.messages.dig(:tax_error)

    # If the invoice was passed as an argument, it means the job was already retried (see end of function)
    result.raise_if_error! if invoice

    # If the invoice is in a retryable state, we'll re-enqueue the job manually, otherwise the job fails
    result.raise_if_error! unless result.invoice&.generating?

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
end
