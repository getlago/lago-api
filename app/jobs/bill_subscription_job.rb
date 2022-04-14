# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  def perform(subscription, timestamp)
    result = Invoices::CreateService.new(
      subscription: subscription,
      timestamp: timestamp,
    ).create

    raise result.throw_error unless result.success?
  end
end
