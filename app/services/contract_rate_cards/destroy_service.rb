# frozen_string_literal: true

module ContractRateCards
  # Removes a rate card from a contract. Authoring is pending-only: once the
  # contract is active its cards are signed.
  class DestroyService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:)
      @contract_rate_card = contract_rate_card
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless contract_rate_card

      if contract_rate_card.contract.locked?
        return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      end

      ActiveRecord::Base.transaction do
        phases = contract_rate_card.rate_phases.to_a
        RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
        contract_rate_card.rate_phases.discard_all!
        contract_rate_card.discard!
      end

      result.contract_rate_card = contract_rate_card
      result
    end

    private

    attr_reader :contract_rate_card
  end
end
