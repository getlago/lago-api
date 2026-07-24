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

    # event_ingested_at is an epoch timestamp (the zset score set by the
    # events-processor). Optional so jobs enqueued before this change deserialize fine.
    def perform(subscription_id, event_ingested_at = nil)
      Subscriptions::FlagRefreshedService.call!(subscription_id, event_ingested_at:)
    end
  end
end
