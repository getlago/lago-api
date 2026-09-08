# frozen_string_literal: true

module BillingSegments
  class ScheduleService < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(customer:, timestamp: Time.current)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.billing_segments = []

      customer.with_advisory_lock!("billing_segments_schedule_customer_#{customer.id}") do
        ActiveRecord::Base.transaction(requires_new: true) do
          due_rate_cards.each { |card| schedule(card) }
        end
      end

      result
    rescue BaseService::FailedResult => error
      result.billing_segments = []
      result.fail_with_error!(error)
    rescue ActiveRecord::RecordInvalid => error
      result.billing_segments = []
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::StatementInvalid => error
      if error.cause&.message&.include?("billing_segments_no_overlapping_periods")
        result.billing_segments = []
        result.single_validation_failure!(field: :billing_segment, error_code: "overlapping_periods")
      else
        raise
      end
    end

    private

    attr_reader :customer, :timestamp

    def due_rate_cards
      ContractRateCard.due_for_billing(timestamp)
        .where(organization_id: customer.organization_id, contracts: {customer_id: customer.id})
        .includes(:rate_phases, rate_card: :rates,
          contract: [:customer, {catalog_plan: {applied_rate_cards: :rate_phases}}])
        .order(:id)
    end

    def schedule(card)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
      segments = segments_to_schedule(card, schedule)
      persisted = card.billing_segments.where(started_at: segments.map(&:started_at)).index_by(&:started_at)

      segments.each do |segment|
        existing = persisted[segment.started_at]

        if existing
          validate_persisted_segment!(existing, segment)
        else
          result.billing_segments << create_segment(card, segment)
        end
      end

      card.update!(next_billing_at: schedule.next_billing_at(after: timestamp))
    end

    def segments_to_schedule(card, schedule)
      segments = schedule.segments_due_by(timestamp)

      if card.billing_segments.exists?
        segments
      else
        # The initial clock skips historical cycles on backdated contracts, but all
        # priced slices of the first billable cycle must still be produced together.
        first = segments.find { it.billing_at >= card.next_billing_at } || segments.last
        segments.select { it.cycle_started_at >= first.cycle_started_at }
      end
    end

    # Resume repeats the last cycle. A retry must preserve its original price snapshot.
    def validate_persisted_segment!(existing, segment)
      if existing.ended_at != BillingSegment.inclusive_end(segment.ended_at) ||
          existing.cycle_started_at != segment.cycle_started_at
        result.single_validation_failure!(field: :billing_segment, error_code: "overlapping_periods").raise_if_error!
      end
    end

    def create_segment(card, segment)
      BillingSegment.create!(
        organization_id: card.organization_id,
        contract: card.contract,
        customer:,
        contract_rate_card: card,
        billing_at: segment.billing_at,
        cycle_started_at: segment.cycle_started_at,
        started_at: segment.started_at,
        ended_at: BillingSegment.inclusive_end(segment.ended_at),
        rate_card_rate: segment.rate,
        rate_override: segment.rate_override,
        pricing_unit: pricing_unit_for(card),
        currency: card.rate_card.currency,
        rate_properties: (segment.rate_override || segment.rate).properties,
        proration_ratio: segment.proration_ratio
      )
    end

    def pricing_unit_for(card)
      code = card.rate_card.applied_pricing_unit_code

      if code.present?
        customer.organization.pricing_units.find_by!(code:)
      end
    end
  end
end
