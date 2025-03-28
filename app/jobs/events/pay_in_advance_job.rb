# frozen_string_literal: true

module Events
  class PayInAdvanceJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_EVENTS"])
        :events
      else
        :default
      end
    end

    retry_on ActiveJob::Uniqueness::JobNotUnique, wait: :polynomially_longer, attempts: 3, jitter: 0.75

    unique :until_executed, on_conflict: :log

    def perform(event)
      Events::PayInAdvanceService.call(event:).raise_if_error!
    ensure
      unlock_unique_job
    end

    def lock_key_arguments
      event = Events::CommonFactory.new_instance(source: arguments.first)
      [event.organization_id, event.external_subscription_id, event.transaction_id]
    end

    def unlock_unique_job
      lock_key = ActiveJob::Uniqueness::LockKey.new(self).key
      Sidekiq.redis { |conn| conn.del(lock_key) }
    rescue => e
      Rails.logger.error "Failed to release lock: #{e.message}"
    end
  end
end
