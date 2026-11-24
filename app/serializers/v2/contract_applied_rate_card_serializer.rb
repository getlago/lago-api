# frozen_string_literal: true

module V2
  class ContractAppliedRateCardSerializer < ModelSerializer
    timestamps :next_billing_at, :created_at, :updated_at, :deleted_at, :scheduled_units_effective_at

    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract.external_id,
        rate_card_code: model.rate_card.code,
        units: units_state.units,
        scheduled_units: units_state.scheduled_term&.units,
        effective_date: format_date(model.effective_date),
        billing_anchor_date: format_date(model.billing_anchor_date),
        **(include?(:rate_phases) ? {rate_phases: rate_phases} : {})
      }
    end

    private

    def units_state
      @units_state ||= begin
        timestamp = model.contract.editable? ? model.effective_date.in_time_zone(model.contract.customer.applicable_timezone) : Time.current
        ContractRateCards::UnitsAtService.call!(contract_rate_card: model, timestamp:)
      end
    end

    def scheduled_units_effective_at
      units_state.scheduled_term&.starts_at
    end

    def rate_phases
      model.rate_phases.order(:position).map do |phase|
        ::V2::RatePhaseSerializer.new(phase).serialize
      end
    end
  end
end
