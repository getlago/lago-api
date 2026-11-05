# frozen_string_literal: true

module V2
  class EventSerializer < ModelSerializer
    timestamps :timestamp

    def serialize
      {
        transaction_id: model.transaction_id,
        external_contract_id: external_contract_id,
        code: model.code,
        precise_total_amount_cents: model.precise_total_amount_cents&.to_s,
        properties: model.properties
      }
    end

    private

    def external_contract_id
      if model.has_attribute?(:external_contract_id)
        model.external_contract_id
      else
        model.external_subscription_id
      end
    end
  end
end
