# frozen_string_literal: true

module V2
  class BillingObligationSerializer < ModelSerializer
    timestamps :cycle_started_at, :billing_at

    def serialize
      {
        external_contract_id: contract.external_id,
        external_customer_id: contract.customer.external_id,
        lago_applied_rate_card_id: contract_rate_card.id,
        applied_rate_card_code: contract_rate_card.rate_card.code,
        cycle_index: obligation.cycle.index + 1,
        billing_scope: obligation.terms.billing_scope,
        rate_phase_code: obligation.cycle.phase.code,
        segments: obligation.segments.map do |segment|
          BillingObligationSegmentSerializer.new(segment, **nested_options, obligation:).serialize
        end
      }
    end

    private

    delegate :contract_rate_card, :obligation, to: :model
    delegate :contract, to: :contract_rate_card

    def billing_at = obligation.billing_at.utc
    def cycle_started_at = obligation.cycle.started_at.utc
  end
end
