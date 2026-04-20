# frozen_string_literal: true

module Subscriptions
  class TerminateDowngradedJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription, timestamp)
      result = Subscriptions::TerminateDowngradedService.new(subscription:, timestamp:).call

      result.raise_if_error!
    end
  end
end
