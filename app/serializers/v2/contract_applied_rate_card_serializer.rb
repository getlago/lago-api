# frozen_string_literal: true

module V2
  class ContractAppliedRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract.external_id,
        rate_card_code: model.rate_card.code,
        units: model.units,
        effective_date: model.effective_date.iso8601,
        ended_date: model.ended_date&.iso8601,
        billing_anchor_date: model.billing_anchor_date.iso8601,
        next_billing_at: model.next_billing_at.iso8601,
        # size counts the loaded collection when the caller preloaded it.
        rate_phases_count: model.rate_phases.size,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
