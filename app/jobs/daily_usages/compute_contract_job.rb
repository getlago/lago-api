# frozen_string_literal: true

module DailyUsages
  class ComputeContractJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ANALYTICS"])
        :analytics
      else
        :low_priority
      end
    end

    retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 6
    unique :until_and_while_executing,
      on_conflict: :log,
      lock_ttl: 3.hours,
      runtime_lock_ttl: 30.minutes

    def perform(contract, timestamp:)
      DailyUsages::ComputeContractService.call!(contract:, timestamp:)
    end

    def lock_key_arguments
      contract = arguments[0]
      timestamp = arguments[1][:timestamp]
      timestamp_in_customer_tz = timestamp.in_time_zone(contract.customer.applicable_timezone)
      [contract.id, timestamp_in_customer_tz.to_date]
    end
  end
end
