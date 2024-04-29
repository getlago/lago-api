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
      skip_charges:,
    )
    return if result.success?

    result.raise_if_error! if invoice || result.invoice.nil? || !result.invoice.generating?

    # NOTE: retry the job with the already created invoice in a previous failed attempt
    self.class.set(wait: 3.seconds).perform_later(
      subscriptions,
      timestamp,
      invoicing_reason:,
      invoice: result.invoice,
      skip_charges:,
    )
  end
end
