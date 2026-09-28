# frozen_string_literal: true

module BillingCycles
  class MaterializeService < BaseService
    Result = BaseResult[:billing_cycles]

    def initialize(contract_rate_card:, cycles:)
      @contract_rate_card = contract_rate_card
      @cycles = cycles
      super
    end

    def call
      result.billing_cycles = BillingCycle.transaction do
        cycles.map do |cycle|
          contract_rate_card.billing_cycles.find_or_create_by!(
            organization_id: contract_rate_card.organization_id,
            cycle_index: cycle.cycle_index,
            started_at: cycle.started_at,
            ended_at: cycle.ended_at,
            timezone: cycle.timezone
          )
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::RecordNotFound
      result.single_validation_failure!(field: :billing_cycle, error_code: "calendar_conflict")
    end

    private

    attr_reader :contract_rate_card, :cycles
  end
end
