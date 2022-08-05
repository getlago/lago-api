# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(subscriptions, timestamp)
    result = Invoices::CreateService.new(
      subscriptions: subscriptions,
      timestamp: timestamp,
    ).create

    result.throw_error unless result.success?
  end
end
