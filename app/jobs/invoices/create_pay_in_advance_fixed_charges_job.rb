# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceFixedChargesJob < ApplicationJob
    def self.retry_delay
      rand(0...16)
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75
    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

    # We acquire a lock on the customer to prevent concurrent pay-in-advance invoice creation.
    # When it fails, it raises a WithAdvisoryLock::FailedToAcquireLock error.
    # If the lock succeeds but another job/request updates the wallet concurrenly, it will raise a ActiveRecord::StaleObjectError error.
    retry_on WithAdvisoryLock::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: 25, wait: ->(_) { CreatePayInAdvanceFixedChargesJob.retry_delay }

    unique :until_executed, on_conflict: :log

    def perform(subscription, timestamp)
      Invoices::PayInAdvance::CreateFixedChargesService.call!(
        subscription:,
        timestamp:
      )
    end
  end
end
