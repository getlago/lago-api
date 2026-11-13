# frozen_string_literal: true

module BillingOperations
  # Creates the initial billing operations when a contract starts.
  class ApplyActivationService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      result.billing_operations = []
      return result unless contract.organization.product_catalog_enabled?

      contract.applied_rate_cards.priced.includes(:rate_card).find_each do |card|
        result.billing_operations.concat(CreateInitialOperationService.call!(
          contract_rate_card: card, causation_type: "contract_activation"
        ).billing_operations)
      end

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract
  end
end
