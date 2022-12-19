# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(subscriptions, timestamp, recurring: false)
    result = Invoices::SubscriptionService.new(
      subscriptions: subscriptions,
      timestamp: timestamp,
      recurring: recurring,
    ).create

    result.throw_error unless result.success?
  end
end
