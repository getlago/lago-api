# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError

  def perform(subscriptions, timestamp, recurring: false)
    result = Invoices::SubscriptionService.new(
      subscriptions:,
      timestamp:,
      recurring:,
    ).create

    result.raise_if_error!
  end
end
