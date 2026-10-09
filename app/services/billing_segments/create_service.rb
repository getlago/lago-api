# frozen_string_literal: true

module BillingSegments
  # Writes a card's calendar slices as rows, in one statement.
  class CreateService < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(contract_rate_card:, billable_segments:, pricing_unit:)
      @contract_rate_card = contract_rate_card
      @billable_segments = billable_segments
      @pricing_unit = pricing_unit
      super
    end

    def call
      # insert_all! rather than a conflict clause: a duplicate here means the caller wrote
      # without subtracting what is already stored, and that is a bug to see, not to absorb.
      rows = billable_segments.map { row_for(it) }
      inserted = BillingSegment.insert_all!(rows, returning: BillingSegment.column_names) # rubocop:disable Rails/SkipsModelValidations

      result.billing_segments = inserted.map { BillingSegment.instantiate(it) }
      result
    end

    private

    attr_reader :contract_rate_card, :billable_segments, :pricing_unit

    # Column values, not associations: the row is written without loading anything.
    def row_for(billable_segment)
      {
        organization_id: contract_rate_card.organization_id,
        contract_id: contract_rate_card.contract_id,
        customer_id: contract.customer_id,
        contract_rate_card_id: contract_rate_card.id,
        cycle_started_at: billable_segment.cycle_started_at,
        started_at: billable_segment.started_at,
        ended_at: BillingSegment.inclusive_end(billable_segment.ended_at),
        billing_at: billable_segment.billing_at,
        rate_card_rate_id: billable_segment.rate&.id,
        rate_override_id: billable_segment.rate_override&.id,
        rate_properties: billable_segment.properties,
        currency: contract_rate_card.rate_card.currency,
        pricing_unit_id: pricing_unit&.id,
        proration_ratio: billable_segment.proration_ratio,
        status: segment_status
      }
    end

    def segment_status
      rate_card = contract_rate_card.rate_card

      if rate_card.product.metered? && rate_card.advance?
        BillingSegment::STATUSES.fetch(:processing)
      else
        BillingSegment::STATUSES.fetch(:pending)
      end
    end

    def contract
      contract_rate_card.contract
    end
  end
end
