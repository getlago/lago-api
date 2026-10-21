# frozen_string_literal: true

module Contracts
  # Terminates every active contract whose planned end has arrived, one job each
  # so a contract that fails does not hold back the others.
  class TerminateAllEndedService < BaseService
    Result = BaseResult

    def initialize(timestamp: Time.current)
      @timestamp = timestamp
      super
    end

    def call
      Contract.due_for_termination(timestamp)
        .joins(:customer)
        .where(customers: {deleted_at: nil})
        .find_each { |contract| Contracts::TerminateJob.perform_later(contract) }

      result
    end

    private

    attr_reader :timestamp
  end
end
