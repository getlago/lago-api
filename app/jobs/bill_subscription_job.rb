# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError

  def perform(subscriptions, timestamp, recurring: false, invoice: nil, skip_charges: false)
    result = Invoices::SubscriptionService.call(
      subscriptions:,
      timestamp:,
      recurring:,
      invoice:,
      skip_charges:,
    )
    return if result.success?

    result.raise_if_error! if invoice || result.invoice.nil? || !result.invoice.generating?

    # NOTE: retry the job with the already created invoice in a previous failed attempt
    self.class.set(wait: 3.seconds).perform_later(
      subscriptions,
      timestamp,
      recurring:,
      invoice: result.invoice,
      skip_charges:,
    )
  end
end
