# frozen_string_literal: true

module Contracts
  # Ends a live contract's lifecycle. An active contract that already ran is
  # terminated; a pending one that never started is canceled instead — two
  # names for the same "no longer live" outcome, so history keeps whether the
  # agreement ever took effect. Both transitions are terminal: a terminated or
  # canceled contract is history and cannot be terminated again.
  #
  # Terminating also closes the billing. The contract ends now, so every card's
  # schedule stops at this instant, and the period still open is written as
  # segments and invoiced. The clock does not bill terminated contracts, so
  # nothing else would.
  class TerminateService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      ActiveRecord::Base.transaction do
        # The clock schedules a customer's cards under this lock, so it cannot
        # write a segment for a card while the termination closes it.
        Customers::LockService.call!(customer: contract.customer, scope: :billing_schedule) do
          # Re-read under lock: a pending contract the clock just activated has
          # taken effect, so it is terminated rather than canceled.
          contract.lock!

          unless contract.pending? || contract.active?
            return result.single_validation_failure!(field: :contract, error_code: "cannot_terminate")
          end

          if contract.active?
            terminate
          else
            contract.update!(status: :canceled, canceled_at: Time.current)
          end
        end
      end

      result.contract = contract
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :contract

    def terminate
      terminated_at = Time.current
      # A planned end that already passed stays the end.
      ended_at = [contract.ended_at, terminated_at].compact.min
      contract.update!(status: :terminated, terminated_at:, ended_at:)

      closing = BillingSegments::ScheduleService.call!(customer: contract.customer, contract:, timestamp: terminated_at)
      BillingSegments::ProcessJob.perform_after_commit(contract.customer_id) if closing.billing_segments.any?
    end
  end
end
