# frozen_string_literal: true

module Contracts
  # Ends a live contract's lifecycle. An active contract that already ran is
  # terminated; a pending one that never started is canceled instead — two
  # names for the same "no longer live" outcome, so history keeps whether the
  # agreement ever took effect. Both transitions are terminal: a terminated or
  # canceled contract is history and cannot be terminated again.
  #
  # Terminating also closes billing: every card stops at the termination
  # instant, and the period still open is written as segments and invoiced.
  # The clock only bills active contracts, so nothing else would bill it.
  class TerminateService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:, timestamp: Time.current)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      # The clock's lock first, then the row: writing a segment takes a key-share lock on the
      # contract row, so the reverse order deadlocks with a running clock.
      Customers::LockService.call(customer: contract.customer, scope: :billing_schedule) do
        # Re-read under lock: a pending contract the clock just activated has
        # taken effect, so it is terminated rather than canceled.
        contract.lock!

        unless contract.pending? || contract.active?
          return result.single_validation_failure!(field: :contract, error_code: "cannot_terminate")
        end

        if contract.active?
          terminate
        else
          contract.update!(status: :canceled, canceled_at: timestamp)
        end
      end

      result.contract = contract
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :contract, :timestamp

    def terminate
      contract.update!(status: :terminated, terminated_at: timestamp)

      closing = BillingSegments::ScheduleFinalSegmentsService.call!(contract:, timestamp: contract.terminated_at)
      BillingSegments::ProcessJob.perform_after_commit(contract.customer_id) if closing.billing_segments.any?
    end
  end
end
