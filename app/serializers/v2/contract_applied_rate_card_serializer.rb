# frozen_string_literal: true

module V2
  class ContractAppliedRateCardSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract.external_id,
        rate_card_code: model.rate_card.code,
        units: model.units,
        effective_date: format_date(model.effective_date),
        billing_anchor_date: format_date(model.billing_anchor_date),
        next_billing_at: format_time(model.next_billing_at),
        **(include?(:rate_phases) ? {rate_phases: rate_phases} : {})
      }
    end

    private

    def rate_phases
      model.rate_phases.order(:position).map do |phase|
        ::V2::RatePhaseSerializer.new(phase).serialize
      end
    end
  end
end
