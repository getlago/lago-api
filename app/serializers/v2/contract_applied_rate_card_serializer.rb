# frozen_string_literal: true

module V2
  class ContractAppliedRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract.external_id,
        rate_card_code: model.rate_card.code,
        units: model.units,
        effective_date: format_date(model.effective_date),
        billing_anchor_date: format_date(model.billing_anchor_date),
        next_billing_at: format_time(model.next_billing_at),
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        **deleted_at_payload
      }
    end
  end
end
