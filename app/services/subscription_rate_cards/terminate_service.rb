# frozen_string_literal: true

module SubscriptionRateCards
  # Terminates a single product-catalog item.
  #
  # Arrears items create pending BillingSegments for periods overlapping the termination
  # window. The final period is clamped to terminated_at and left pending for the clock
  # processor to invoice. The item's next_billing_at is set to terminated_at so the
  # due-items scope will no longer treat it as an unbilled future cycle.
  #
  # Advance items do not create a BillingSegment: the current period was already billed
  # up front. This service only sets ended_at; the subscription-level termination flow
  # handles any unused-period credit note separately.
  class TerminateService < BaseService
    Result = BaseResult[:subscription_rate_card, :billing_segments]

    def initialize(subscription_rate_card:, terminated_at: Time.current)
      @subscription_rate_card = subscription_rate_card
      @terminated_at = terminated_at
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless subscription_rate_card

      result.billing_segments = []
      return result if subscription_rate_card.ended_at.present?

      ActiveRecord::Base.transaction do
        result.billing_segments = final_segments
        subscription_rate_card.update!(termination_attributes)
      end

      result.subscription_rate_card = subscription_rate_card
      result
    end

    private

    attr_reader :subscription_rate_card, :terminated_at

    delegate :organization, :subscription, :customer, to: :subscription_rate_card

    def termination_attributes
      attributes = {ended_at: terminated_at}
      return attributes unless arrears?

      attributes.merge(next_billing_at: terminated_at)
    end

    # Every unbilled period up to the termination, the last one clamped to it. Advance
    # cards are absent by design: their period was paid up front, and what is owed back is
    # a credit note rather than a segment.
    def final_segments
      return [] unless arrears?

      build = ::Billing::Schedules::BuildService.call(
        subscription_rate_card:,
        plan_rate_cards:,
        ends_at: terminated_at
      )
      return [] if build.failure?

      build.schedule.cycles_overlapping(termination_window).flat_map do |cycle|
        ::Billing::Segments.within(cycle.from...cycle.to, rates:).map do |segment|
          persist(cycle, segment)
        end
      end
    end

    # A cancellation booked for later closes the periods from today onward; one taking
    # effect now closes only the period it lands in.
    def termination_window
      @termination_window ||= if terminated_at.future?
        Time.current...terminated_at
      else
        terminated_at.beginning_of_day...terminated_at
      end
    end

    def persist(cycle, segment)
      BillingSegment.create!(
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        billing_at: terminated_at,
        period_from: segment.from,
        period_to: covered_until(segment),
        rate_card_rate: segment.rate,
        rate_override: cycle.phase.override,
        rate_properties: (cycle.phase.override || segment.rate).properties,
        proration_ratio: proration_ratio(cycle, segment)
      )
    end

    # Cycle ends are exclusive boundaries, so the last instant they cover is a moment
    # before. The termination is not a boundary — it is already the last instant of service.
    def covered_until(segment)
      return terminated_at if segment.to == terminated_at

      segment.to - Rational(1, 1_000_000)
    end

    def proration_ratio(cycle, segment)
      return 1 unless subscription_rate_card.proration?

      cycle.calendar.elapsed_ratio(segment.from, segment.to)
    end

    # Every rate the card has carried: which one prices a segment is decided by its
    # effective date, so narrowing the set here would hide the one in force.
    def rates
      subscription_rate_card.rate_card.rates.order(:effective_from)
    end

    def plan_rate_cards
      subscription.plan.applied_rate_cards.to_a
    end

    def arrears?
      subscription_rate_card.rate_card.arrears?
    end
  end
end
