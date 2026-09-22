# frozen_string_literal: true

module V2
  # A segment the calendar would produce, not one that was stored: the shape a QA preview
  # reads to answer "what bills, when, at what price".
  #
  # `period_to` is the last instant the window covers, the same inclusive end the stored rows
  # carry — BillingSegment.inclusive_end is the one place that conversion lives.
  class BillableSegmentSerializer < ModelSerializer
    def serialize
      {
        external_contract_id: contract.external_id,
        external_customer_id: contract.customer.external_id,
        lago_applied_rate_card_id: contract_rate_card.id,
        applied_rate_card_code: contract_rate_card.rate_card.code,
        # One-based, as the cycles payload has always shown it.
        cycle_index: segment.cycle_index + 1,
        cycle_started_at: segment.cycle_started_at.iso8601,
        period_from: segment.started_at.iso8601,
        period_to: BillingSegment.inclusive_end(segment.ended_at).iso8601,
        billing_at: segment.billing_at.iso8601,
        proration_ratio: segment.proration_ratio,
        rate_phase_code: segment.rate_phase_code,
        lago_rate_id: segment.rate&.id,
        rate_code: segment.rate&.code,
        lago_rate_override_id: segment.rate_override&.id,
        properties: segment.properties
      }
    end

    private

    def segment
      model.billable_segment
    end

    def contract_rate_card
      model.contract_rate_card
    end

    def contract
      contract_rate_card.contract
    end
  end
end
