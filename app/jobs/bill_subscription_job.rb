# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  retry_on Sequenced::SequenceError

  def perform(subscription, timestamp)
    result = Invoices::CreateService.new(
      subscription: subscription,
      timestamp: timestamp,
    ).create

    raise result.throw_error unless result.success?
  end
end
