# frozen_string_literal: true

module Contracts
  # Ends a live contract's lifecycle. An active contract that already ran is
  # terminated; a pending one that never started is canceled instead — two
  # names for the same "no longer live" outcome, so history keeps whether the
  # agreement ever took effect. Both transitions are terminal: a terminated or
  # canceled contract is history and cannot be terminated again.
  #
  # Lifecycle state only. This does not itself stop billing: the schedule
  # bounds on contract.ended_at and each card's ended_date, not on status, so
  # the billing cutoff (bringing those dates in, prorating the open period) is
  # owned by the billing engine and applied there, not from this service.
  class TerminateService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      unless contract.pending? || contract.active?
        return result.single_validation_failure!(field: :contract, error_code: "cannot_terminate")
      end

      if contract.active?
        contract.update!(status: :terminated, terminated_at: Time.current)
      else
        contract.update!(status: :canceled, canceled_at: Time.current)
      end

      result.contract = contract
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract
  end
end
