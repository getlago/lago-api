# frozen_string_literal: true

class BillSubscriptionByTimebasedEventJob < ApplicationJob
  queue_as "billing"

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError

  def perform(subscription, timestamp, timebased_event:, async: true)
    service = async ? Invoices::SubscriptionService : Invoices::SubscriptionSyncService

    result = service.call(
      subscriptions: [subscription],
      timestamp:,
      recurring: false,
      invoice: nil,
    )
    if result.success? && !async
      return result
    end

    result.raise_if_error! if result.invoice.nil? || !result.invoice.generating?
  end
end
