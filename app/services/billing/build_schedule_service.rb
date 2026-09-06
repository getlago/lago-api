# frozen_string_literal: true

module Billing
  # Loads one subscription rate card out of the database and hands back the schedule that
  # describes it. This is the only class in the engine that touches ActiveRecord: below it
  # every timestamp, rate and phase arrives as an argument.
  #
  # Every rate of the card is loaded, not the slice overlapping some range. A card holds a
  # handful of rates, the walk needs all of them to know where the cadence changes, and a
  # window query per call site was three copies of the same LEAD(...) SQL.
  class BuildScheduleService < BaseService
    Result = BaseResult[:schedule]

    # The anchor policy defaults to Realigning, which is what every call site does today.
    # When the product decides where the setting lives, this service is the one place that
    # reads it: nothing below here knows the setting exists.
    def initialize(subscription_rate_card:, plan_rate_card: nil, ends_at: nil, anchor_policy: AnchorPolicy::Realigning)
      @subscription_rate_card = subscription_rate_card
      @plan_rate_card = plan_rate_card
      @requested_ends_at = ends_at
      @anchor_policy = anchor_policy
      super
    end

    def call
      return result.not_found_failure!(resource: "rate") if rates.empty?

      result.schedule = Schedule.new(
        anchor_date: subscription_rate_card.billing_anchor_date,
        timezone: customer.applicable_timezone,
        starts_at: subscription_rate_card.card_started_at,
        ends_at:,
        terms: Terms.new(timing: rate_card.billing_timing.to_sym, prorated: rate_card.proration?),
        rates: RateTimeline.new(rates),
        phases:,
        anchor_policy:
      )
      result
    end

    private

    attr_reader :subscription_rate_card, :plan_rate_card, :requested_ends_at, :anchor_policy

    delegate :rate_card, to: :subscription_rate_card

    def rates
      @rates ||= rate_card.rates.order(:effective_from).to_a
    end

    def customer
      subscription_rate_card.subscription.customer
    end

    # An explicit end wins over the card's own: termination asks for a schedule stopping
    # at the termination instant, which the card does not carry until it is terminated.
    def ends_at
      requested_ends_at || subscription_rate_card.ended_at
    end

    def phases
      rate_phases.phases.map do |rate_phase|
        Schedule::Phase.new(
          position: rate_phase.position,
          cycle_count: rate_phase.billing_interval_cycle_count,
          code: rate_phase.code,
          override: rate_phase.rate_override
        )
      end
    end

    def rate_phases
      SubscriptionRateCards::ResolveRatePhasesService.call!(
        subscription_rate_card:,
        plan_rate_cards: [resolved_plan_rate_card].compact
      ).rate_phases
    end

    # The plan entry holds the phases a card falls back to when the subscription carries
    # none of its own. `plan_rate_card` is a hint that spares the lookup for a caller that
    # already holds it — never the source of truth.
    #
    # Absent, the entry is looked up here. Resolving against an empty list instead would
    # silently price every cycle at the base rate, dropping every phase the plan configured
    # without raising anything.
    #
    # Given, it is verified. An entry belonging to another card would resolve that card's
    # phases onto this one — a wrong price with no symptom at all — so it raises instead.
    def resolved_plan_rate_card
      return plan_rate_card_of_subscription_plan if plan_rate_card.nil?
      return plan_rate_card if plan_rate_card.rate_card_id == subscription_rate_card.rate_card_id

      raise ArgumentError,
        "plan_rate_card #{plan_rate_card.id} prices rate card #{plan_rate_card.rate_card_id}, " \
        "not #{subscription_rate_card.rate_card_id}"
    end

    def plan_rate_card_of_subscription_plan
      subscription_rate_card.subscription.plan.applied_rate_cards
        .find { it.rate_card_id == subscription_rate_card.rate_card_id }
    end
  end
end
