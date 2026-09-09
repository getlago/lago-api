# frozen_string_literal: true

module BillingSegments
  # Persists the calendar's due slices. The clock is both the lower billing
  # bound (backdated contracts can join the current period) and the next wake-up.
  class ScheduleService < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(customer:, timestamp: Time.current)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.billing_segments = []

      if customer.nil?
        return result.not_found_failure!(resource: "customer")
      end

      scheduled = []
      ActiveRecord::Base.transaction do
        Customers::LockService.call!(customer:, scope: :billing_schedule) do
          due_cards.find_each do |card|
            scheduled.concat(schedule_card(card))
          end
        end
      end

      result.billing_segments = scheduled
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :timestamp

    def due_cards
      ContractRateCard.joins(:contract)
        .where(organization_id: customer.organization_id, next_billing_at: ..timestamp)
        .where(contracts: {customer_id: customer.id, status: %w[active terminated], started_at: ..timestamp})
        .includes(:rate_card, contract: :customer)
    end

    def schedule_card(card)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
      scheduled = schedule.segments_due_by(timestamp, billing_from: card.next_billing_at).filter_map do |segment|
        persist_segment(card, segment)
      end

      # nil means the schedule is exhausted, so this card is no longer due.
      card.update!(next_billing_at: schedule.next_billing_at(after: timestamp))
      scheduled
    end

    def persist_segment(card, segment)
      # Resuming replays the last cycle, which can contain several segments.
      # Keep existing snapshots and statuses intact, including on a stale-clock retry.
      if card.billing_segments.exists?(started_at: segment.started_at)
        return
      end

      card.billing_segments.create!(
        organization: customer.organization,
        customer:,
        contract: card.contract,
        cycle_started_at: segment.cycle_started_at,
        started_at: segment.started_at,
        ended_at: BillingSegment.inclusive_end(segment.ended_at),
        billing_at: segment.billing_at,
        rate_card_rate: segment.rate,
        rate_override: segment.rate_override,
        rate_properties: (segment.rate_override || segment.rate).properties,
        currency: card.rate_card.currency,
        pricing_unit: pricing_unit(card),
        proration_ratio: segment.proration_ratio,
        status: :pending
      )
    end

    def pricing_unit(card)
      code = card.rate_card.applied_pricing_unit_code

      if code.present?
        unit = customer.organization.pricing_units.find_by(code:)

        if unit.nil?
          result.not_found_failure!(resource: "pricing_unit").raise_if_error!
        end

        unit
      end
    end
  end
end
