# frozen_string_literal: true

module BillingOperations
  class CreateService < BaseService
    Result = BaseResult[:operation]

    def initialize(contract_rate_card:, action_type:, reason:, planned_operation:, operation_id: nil)
      @operation_id = operation_id
      @contract_rate_card = contract_rate_card
      @action_type = action_type
      @reason = reason
      @planned_operation = planned_operation
      super
    end

    def call
      return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card

      result.operation = contract_rate_card.billing_operations.create!(
        id: operation_id,
        organization: contract_rate_card.organization,
        customer: contract_rate_card.contract.customer,
        action_type:,
        reason:,
        billing_at: planned_operation.billing_at,
        target_cycle_started_at: planned_operation.cycle_started_at,
        coverage_started_at: planned_operation.coverage_started_at,
        coverage_ended_at: planned_operation.coverage_ended_at
      ) do |operation|
        obligation = planned_operation.obligation
        obligation.segments.each_with_index do |segment, position|
          operation.segments.build(organization: contract_rate_card.organization, position:,
            started_at: segment.started_at, ended_at: segment.ended_at,
            proration_ratio: obligation.proration_ratio_for(segment),
            rate_card_rate: segment.rate, rate_override: obligation.cycle.phase.rate_override)
        end
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :action_type, :reason, :planned_operation, :operation_id
  end
end
