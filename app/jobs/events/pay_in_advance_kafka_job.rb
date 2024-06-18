# frozen_string_literal: true

module Events
  class PayInAdvanceKafkaJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_EVENTS'])
        :events
      else
        :default
      end
    end

    # NOTE: This job is called from the Kafka consumer, so we don't need to worry about locking
    #       It's goal is only to enqueue the PayInAdvanceJob to be processed by Sidekiq
    #       taking advantage of the "unique" logic
    def perform(event)
      Events::PayInAdvanceJob.perform_later(event)
    end
  end
end
