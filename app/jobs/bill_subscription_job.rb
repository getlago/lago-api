# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as 'billing'

  def perform(subscription, timestamp)
    # TODO
  end
end
