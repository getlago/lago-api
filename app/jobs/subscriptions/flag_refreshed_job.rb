# frozen_string_literal: true

module Subscriptions
  class FlagRefreshedJob < ApplicationJob
    queue_as :events

    def perform(subscription_id)
      Subscriptions::FlagRefreshedService.call!(subscription_id)
    end
  end
end
