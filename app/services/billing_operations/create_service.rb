# frozen_string_literal: true

module BillingOperations
  class CreateService < BaseService
    Result = BaseResult[:operation]

    def initialize(contract_rate_card:, action_type:, reason:, planned_operation:)
      @contract_rate_card = contract_rate_card
      @action_type = action_type
      @reason = reason
      @planned_operation = planned_operation
      super
    end

    def call
      return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card

      segment = planned_operation.segment
      result.operation = contract_rate_card.billing_operations.create!(
        organization: contract_rate_card.organization,
        customer: contract_rate_card.contract.customer,
        action_type:,
        reason:,
        billing_at: planned_operation.billing_at,
        target_cycle_started_at: planned_operation.cycle_started_at,
        coverage_started_at: segment.started_at,
        coverage_ended_at: segment.ended_at
      ) do |operation|
        operation.segments.build(
          organization: contract_rate_card.organization, position: 0,
          started_at: segment.started_at, ended_at: segment.ended_at,
          rate_card_rate: segment.rate, rate_override: segment.rate_override, proration_ratio: segment.proration_ratio
        )
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :action_type, :reason, :planned_operation
  end
end
