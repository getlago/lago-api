# frozen_string_literal: true

class Subscriptions::RecalculateUsageJob < ApplicationJob
  queue_as :default # TODO: use an alerting queue?

  def perform(subscription_id)
    # TODO(alert): Implement
  end
end
