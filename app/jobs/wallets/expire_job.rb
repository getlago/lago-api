# frozen_string_literal: true

module Wallets
  class ExpireJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    unique :until_executed, on_conflict: :log

    def perform(wallet)
      Wallets::ExpireService.call!(wallet:)
    end
  end
end
