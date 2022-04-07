# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  def perform(subscription, timestamp)
    result = InvoicesService.new.create(
      subscription: subscription,
      timestamp: timestamp,
    )

    raise result.throw_error unless result.success?
  end
end
