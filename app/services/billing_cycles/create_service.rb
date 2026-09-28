# frozen_string_literal: true

module BillingCycles
  class CreateService < BaseService
    Result = BaseResult[:billing_cycle]

    def initialize(contract_rate_card:, cycle:)
      @contract_rate_card = contract_rate_card
      @cycle = cycle
      super
    end

    def call
      result.billing_cycle = contract_rate_card.billing_cycles.find_or_create_by!(
        cycle_index: cycle.index,
        organization_id: contract_rate_card.organization_id,
        started_at: cycle.started_at,
        ended_at: cycle.ended_at,
        timezone: cycle.calendar.timezone
      )

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::RecordNotFound
      # A unique cycle index or start exists, but with different calendar attributes.
      result.single_validation_failure!(field: :billing_cycle, error_code: "calendar_conflict")
    end

    private

    attr_reader :contract_rate_card, :cycle
  end
end
