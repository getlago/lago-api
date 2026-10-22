# frozen_string_literal: true

module Contracts
  class TerminateJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    unique :until_executing, on_conflict: :log

    retry_on BaseService::LockAcquisitionFailure, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(contract)
      # Left alone when terminated by hand, or given a later end, since it was enqueued.
      if Contract.due_for_termination(Time.current).exists?(id: contract.id)
        Contracts::TerminateService.call!(contract:, timestamp: contract.ended_at)
      end
    end
  end
end
