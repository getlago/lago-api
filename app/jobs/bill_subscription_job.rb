# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  def perform(subscription, timestamp)
    InvoicesService.new.create(
      subscription: subscription,
      timestamp: timestamp,
    )
  end
end
