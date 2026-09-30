# frozen_string_literal: true

module Contracts
  # Activates every pending contract whose start has arrived, one job each so a
  # contract that fails does not hold back the others.
  class ActivateAllPendingService < BaseService
    Result = BaseResult

    def initialize(timestamp: Time.current)
      @timestamp = timestamp
      super
    end

    def call
      Contract.due_for_activation(timestamp)
        .joins(:customer)
        .where(customers: {deleted_at: nil})
        .find_each { |contract| Contracts::ActivateJob.perform_later(contract) }

      result
    end

    private

    attr_reader :timestamp
  end
end
