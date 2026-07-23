# frozen_string_literal: true

module Subscriptions
  class FlagRefreshedJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"])
        :alerts_high_priority
      else
        :default
      end
    end

    def perform(subscription_id)
      Subscriptions::FlagRefreshedService.call!(subscription_id)
    end
  end
end
