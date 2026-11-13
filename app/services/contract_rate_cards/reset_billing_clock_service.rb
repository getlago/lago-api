# frozen_string_literal: true

module ContractRateCards
  # Sets a card's clock to the billing date its current schedule gives the
  # period around the timestamp. Built from the stored lifecycle and phases, so
  # a card whose schedule cannot be built keeps its clock, and so does a card still
  # owing an obligation before the timestamp (ContractRateCard#owes_billing_before?).
  # A card with no periodic action, or whose schedule has run out, has no next
  # obligation: its clock is cleared.
  class ResetBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card, :planned_operation]

    def initialize(
      contract_rate_card:,
      timestamp: Time.current,
      schedule: Billing::RateCards::BuildScheduleService.call(contract_rate_card:).schedule
    )
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      @schedule = schedule
      super
    end

    def call
      if contract_rate_card.periodic_billing_action.nil?
        contract_rate_card.update!(next_billing_at: nil)
      elsif schedule && !contract_rate_card.owes_billing_before?(timestamp)
        result.planned_operation = BillingOperations::Schedule::BuildPlannedOperation.call!(
          contract_rate_card:, schedule:, at: timestamp
        ).planned_operation
        contract_rate_card.update!(next_billing_at: result.planned_operation&.billing_at)
      end

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :timestamp, :schedule
  end
end
