# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
