# frozen_string_literal: true

module BillingCycles
  # Producer lane, scoped to ONE customer. For every due product overlapping the
  # scheduling range it writes a billing_cycle and advances that item's clock — catching a
  # behind clock up one period at a time. The whole customer runs in one transaction, so
  # the consumer sees the customer's whole set or nothing (completeness), and the clock
  # never advances without a durable record (money-safety). The per-customer advisory
  # lock serialises concurrent runs; the unique (product, period_from) index is the
  # idempotency backstop.
  #
  # A customer holds few items, so plain create!/update! is both readable and fast; the
  # scale lives in the fan-out (one job per customer), not in bulk-writing one customer.
  #
  # Rate effective dates are used only to split service periods. Pricing is still
  # computed later by resolving the rate at each billing_cycle.period_from.
  class ScheduleService < BaseService
    OVERLAP_CONSTRAINT = "billing_cycles_no_overlapping_periods"
    UNIQUE_PERIOD_INDEX = "index_billing_cycles_on_product_and_period"

    Result = BaseResult[:billing_cycles]

    def initialize(customer:, range: Time.current..Time.current)
      @customer = customer
      @range = range
      super
    end

    def call
      result.billing_cycles = []

      customer.with_advisory_lock("billing_cycle_schedule_customer_#{customer.id}") do
        ActiveRecord::Base.transaction do
          due_items.each { |subscription_rate_card| schedule(subscription_rate_card) }
        end
      end

      result
    rescue ActiveRecord::StatementInvalid => e
      raise unless billing_cycle_period_conflict?(e)

      result.billing_cycles = []
      result.single_validation_failure!(field: :billing_cycle, error_code: "overlapping_periods")
    end

    private

    attr_reader :customer, :range

    def due_items
      customer.subscription_rate_cards
        .where(started_at: ..range_end)
        .where("ended_at IS NULL OR ended_at >= ?", range_begin)
        .includes(:rate_phases, subscription: {plan: {applied_rate_cards: :rate_phases}})
    end

    def schedule(subscription_rate_card)
      rates = rates_for(subscription_rate_card)
      return if rates.empty?

      dates = BillingPeriods::DatesService.from_subscription_rate_card(
        subscription_rate_card,
        rates:,
        rate_phases: rate_phases_for(subscription_rate_card),
        range:,
        options: dates_options(subscription_rate_card)
      )
      return if dates.periods.empty?

      # TODO: Consider moving this loop to import! or batch inserting BillingCycle rows.
      dates.periods.each do |period|
        result.billing_cycles << BillingCycle.create!(
          organization: subscription_rate_card.organization,
          subscription: subscription_rate_card.subscription,
          customer:,
          subscription_rate_card:,
          billing_at: period.billing_at,
          period_from: period.period_from,
          period_to: period.period_to
        )
      end

      advance_clock(subscription_rate_card, dates.next_billing_at)
    end

    def range_begin
      @range_begin ||= range.begin.to_date.beginning_of_day.utc
    end

    def range_end
      @range_end ||= range.end.to_date.end_of_day.utc
    end

    # TODO: Move this window query to a Scenic view if rate-range lookups become shared
    def rates_for(subscription_rate_card)
      ranked_rates = subscription_rate_card.rate_card.rates
        .select(
          "rate_card_rates.*, " \
            "LEAD(rate_card_rates.effective_from) OVER " \
            "(ORDER BY rate_card_rates.effective_from) AS next_effective_from"
        )

      RateCardRate
        .from(ranked_rates, :rate_card_rates)
        .where("effective_from <= ?", range_end)
        .where("next_effective_from IS NULL OR next_effective_from >= ?", range_begin)
        .order(:effective_from)
    end

    def dates_options(subscription_rate_card)
      BillingPeriods::DatesService::Options.new(
        timezone: subscription_rate_card.subscription.customer.applicable_timezone,
        exclude_out_of_range: true,
        realign_billing_anchor: true
      )
    end

    def rate_phases_for(subscription_rate_card)
      SubscriptionRateCards::ResolveRatePhasesService.call!(
        subscription_rate_card:,
        plan_rate_cards: plan_rate_cards_for(subscription_rate_card.subscription)
      ).rate_phases
    end

    def plan_rate_cards_for(subscription)
      @plan_rate_cards_by_subscription_id ||= {}
      @plan_rate_cards_by_subscription_id[subscription.id] ||= subscription.plan.applied_rate_cards.to_a
    end

    def advance_clock(subscription_rate_card, next_billing_at)
      return unless next_billing_at
      return if subscription_rate_card.next_billing_at > range_end
      return if next_billing_at <= subscription_rate_card.next_billing_at

      subscription_rate_card.update!(next_billing_at: next_billing_at)
    end

    def billing_cycle_period_conflict?(error)
      error_message = error.cause&.message || error.message

      error_message.include?(OVERLAP_CONSTRAINT) || error_message.include?(UNIQUE_PERIOD_INDEX)
    end
  end
end
