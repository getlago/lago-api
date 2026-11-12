# frozen_string_literal: true

module BillingOperations
  class CreateReconciliationService < BaseService
    Result = BaseResult[:operation]

    def initialize(contract_rate_card:, causation_type:, planned_operation:)
      @contract_rate_card = contract_rate_card
      @causation_type = causation_type
      @planned_operation = planned_operation
      super
    end

    def call
      created = CreateService.call!(
        contract_rate_card:,
        action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage),
        causation_type:,
        planned_operation:
      )
      result.operation = created.operation
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :contract_rate_card, :causation_type, :planned_operation
  end
end
