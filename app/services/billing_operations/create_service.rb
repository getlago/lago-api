# frozen_string_literal: true

module BillingOperations
  class CreateService < BaseService
    Result = BaseResult[:operation]

    def initialize(contract_rate_card:, action_type:, causation_type:, planned_operation:)
      @contract_rate_card = contract_rate_card
      @action_type = action_type
      @causation_type = causation_type
      @planned_operation = planned_operation
      super
    end

    def call
      return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card

      result.operation = contract_rate_card.billing_operations.create!(
        organization: contract_rate_card.organization,
        customer: contract_rate_card.contract.customer,
        action_type:,
        causation_type:,
        billing_at: planned_operation.billing_at,
        target_cycle_started_at: planned_operation.cycle_started_at
      )
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :action_type, :causation_type, :planned_operation
  end
end
