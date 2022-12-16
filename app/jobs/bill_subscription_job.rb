# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(subscriptions, timestamp, invoice_source: :initial)
    result = Invoices::SubscriptionService.new(
      subscriptions: subscriptions,
      timestamp: timestamp,
      invoice_source: invoice_source,
    ).create

    result.throw_error unless result.success?
  end
end
