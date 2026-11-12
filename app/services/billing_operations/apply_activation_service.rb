# frozen_string_literal: true

module BillingOperations
  # Initializes periodic billing cursors when a contract starts.
  class ApplyActivationService < BaseService
    Result = BaseResult

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result unless contract.organization.product_catalog_enabled?

      contract.applied_rate_cards.priced.includes(:rate_card).find_each do |card|
        ContractRateCards::InitializeBillingClockService.call!(contract_rate_card: card)
      end

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract
  end
end
