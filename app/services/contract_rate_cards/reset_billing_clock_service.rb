# frozen_string_literal: true

module ContractRateCards
  # Saved due work keeps its wake date; only completed coverage anchors a new plan.
  class ResetBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card, :schedule, :planned_operation]

    def initialize(contract_rate_card:, timestamp: Time.current)
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      super
    end

    def call
      if contract_rate_card.periodic_billing_action && contract_rate_card.rate_card.rates.to_a.any?
        result.schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      end

      pending = contract_rate_card.earliest_pending_periodic_operation
      next_billing_at = if pending && pending.billing_at <= timestamp
        pending.billing_at
      elsif result.schedule
        result.planned_operation = BillingOperations::Schedule::BuildPlannedOperation.call!(
          schedule: result.schedule, **planning
        ).planned_operation
        result.planned_operation&.billing_at
      end
      contract_rate_card.update!(next_billing_at:) unless contract_rate_card.next_billing_at == next_billing_at
      result.contract_rate_card = contract_rate_card
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :timestamp

    def planning
      previous = contract_rate_card.latest_completed_periodic_operation
      previous ? {after_operation: previous} : {at: contract_rate_card.effective_date_in_customer_timezone}
    end
  end
end
