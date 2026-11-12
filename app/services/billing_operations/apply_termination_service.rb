# frozen_string_literal: true

module BillingOperations
  # The caller holds the customer billing lock. Keep overdue cursors, move future arrears
  # closes to the contract end, and let successful billing advance through remaining cycles.
  class ApplyTerminationService < BaseService
    Result = BaseResult

    def initialize(contract:, timestamp:)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      contract.applied_rate_cards.with_discarded.includes(:rate_card, contract: :customer).find_each do |contract_rate_card|
        contract_rate_card.billing_operations.pending
          .where("billing_at > :timestamp OR target_cycle_started_at >= :ends_at", timestamp:, ends_at:)
          .find_each { it.update!(cancelled_at: timestamp, cancelled_causation_type: "contract_termination") }
        next if contract_rate_card.discarded?

        action = contract_rate_card.periodic_billing_action
        next unless action

        if action.in?(%w[renew_fixed_advance renew_recurring_metered_advance])
          if contract_rate_card.next_billing_at && contract_rate_card.next_billing_at >= ends_at
            contract_rate_card.update!(next_billing_at: nil)
          end
        elsif !contract_rate_card.next_billing_at || contract_rate_card.next_billing_at > timestamp
          schedule_final_close(contract_rate_card, action)
        end
      end
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract, :timestamp

    def ends_at
      [contract.ended_at, contract.terminated_at].compact.min || timestamp
    end

    def schedule_final_close(contract_rate_card, action)
      return unless contract_rate_card.rate_card.rates.exists?

      schedule = BuildScheduleService.call!(contract_rate_card:).schedule
      previous = contract_rate_card.billing_operations.periodic.completed.where(action_type: action)
        .order(:target_cycle_started_at, :billing_at, :id).last
      timezone = contract.customer.applicable_timezone
      cycle = schedule.cycle_at(previous&.target_cycle_started_at || contract_rate_card.effective_date.in_time_zone(timezone))
      planned = schedule.next_planned_operation(cycle, action_type: action, after: previous&.billing_at)
      contract_rate_card.update!(next_billing_at: planned&.billing_at)
    end
  end
end
