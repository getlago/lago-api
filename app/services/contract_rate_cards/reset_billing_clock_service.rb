# frozen_string_literal: true

module ContractRateCards
  # Moves a card's clock to its next obligation: the first falling due after the last
  # completed billing, or the card's first one when nothing was billed yet. Owed work is
  # never skipped, whatever changed in the schedule since. A card whose schedule cannot be
  # built keeps its clock; one with no periodic action, or nothing left to bill, has none.
  class ResetBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card, :planned_operation]

    def initialize(
      contract_rate_card:,
      schedule: Billing::RateCards::BuildScheduleService.call(contract_rate_card:).schedule
    )
      @contract_rate_card = contract_rate_card
      @schedule = schedule
      super
    end

    def call
      if action_type.nil?
        contract_rate_card.update!(next_billing_at: nil)
      elsif schedule
        result.planned_operation = BillingOperations::Schedule::BuildPlannedOperation.call!(
          schedule:, **planning
        ).planned_operation
        contract_rate_card.update!(next_billing_at: result.planned_operation&.billing_at)
      end

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :schedule

    def action_type
      @action_type ||= contract_rate_card.periodic_billing_action
    end

    # A billing can belong to an earlier cycle than its instant, so planning walks from
    # the cycle it billed.
    def planning
      if last_billing
        {after_operation: last_billing}
      else
        {at: contract_rate_card.effective_date_in_customer_timezone}
      end
    end

    def last_billing
      return @last_billing if defined?(@last_billing)

      @last_billing = contract_rate_card.billing_operations.periodic.completed
        .where(organization_id: contract_rate_card.organization_id, action_type:, cancelled_at: nil)
        .order(billing_at: :desc, created_at: :desc, id: :desc)
        .first
      @last_billing
    end
  end
end
