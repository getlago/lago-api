# frozen_string_literal: true

module ContractRateCards
  # Removes a rate card from a contract. Authoring is pending-only: once the
  # contract is active its cards are signed.
  class DestroyService < BaseService
    Result = BaseResult[:contract_rate_card]

    activity_loggable(
      action: "contract_rate_card.deleted",
      record: -> { contract_rate_card },
      condition: -> { emit_events }
    )

    def initialize(contract_rate_card:, emit_events: true)
      @contract_rate_card = contract_rate_card
      @emit_events = emit_events
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless contract_rate_card

      # Locked so the editable check holds: the clock may activate the contract meanwhile.
      contract_rate_card.contract.with_lock do
        unless contract_rate_card.contract.editable?
          return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
        end

        # Phase moves renumber under the card lock; discarding the phases without
        # it could lock them in the opposite order and deadlock.
        contract_rate_card.lock!

        contract_rate_card.association(:rate_phases).reset
        phases = contract_rate_card.rate_phases.to_a
        RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
        contract_rate_card.rate_phases.discard_all!
        contract_rate_card.discard!
        if emit_events
          SendWebhookJob.perform_after_commit("contract_rate_card.deleted", contract_rate_card)
        end
      end

      result.contract_rate_card = contract_rate_card
      result
    end

    private

    attr_reader :contract_rate_card, :emit_events
  end
end
