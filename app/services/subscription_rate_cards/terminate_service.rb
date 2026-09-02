# frozen_string_literal: true

module SubscriptionRateCards
  # Terminates a single product-catalog item.
  #
  # Arrears items create pending BillingCycles for periods overlapping the termination
  # window. The final period is clamped to terminated_at and left pending for the clock
  # processor to invoice. The item's next_billing_at is set to terminated_at so the
  # due-items scope will no longer treat it as an unbilled future cycle.
  #
  # Advance items do not create a BillingCycle: the current period was already billed
  # up front. This service only sets ended_at; the subscription-level termination flow
  # handles any unused-period credit note separately.
  class TerminateService < BaseService
    Result = BaseResult[:subscription_rate_card, :billing_cycles]

    def initialize(subscription_rate_card:, terminated_at: Time.current)
      @subscription_rate_card = subscription_rate_card
      @terminated_at = terminated_at
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless subscription_rate_card

      result.billing_cycles = []
      return result if subscription_rate_card.ended_at.present?

      ActiveRecord::Base.transaction do
        result.billing_cycles = final_cycles
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

    def final_cycles
      return [] unless arrears?

      dates.periods.filter_map { |period| billing_cycle_for(period) }
    end

    # Termination emits every period overlapping the termination window instead of
    # waiting for the regular arrears/advance billing boundary.
    def dates
      @dates ||= BillingPeriods::DatesService.from_subscription_rate_card(
        subscription_rate_card,
        rates:,
        rate_phases:,
        range: termination_range,
        options: dates_options
      )
    end

    def termination_range
      if terminated_at.future?
        Time.current..terminated_at
      else
        terminated_at..terminated_at
      end
    end

    def billing_cycle_for(period)
      BillingCycle.create!(
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        billing_at: terminated_at,
        period_from: period.period_from,
        period_to: period.period_to,
        rate_card_rate: period.rate,
        rate_override: period.rate_override,
        rate_properties: period.rate_properties,
        proration_ratio: period.proration_ratio
      )
    end

    def rates
      ranked_rates = subscription_rate_card.rate_card.rates
        .select(
          "rate_card_rates.*, " \
            "LEAD(rate_card_rates.effective_from) OVER " \
            "(ORDER BY rate_card_rates.effective_from) AS next_effective_from"
        )

      RateCardRate
        .from(ranked_rates, :rate_card_rates)
        .where("effective_from <= ?", termination_range.end.end_of_day)
        .where("next_effective_from IS NULL OR next_effective_from >= ?", termination_range.begin.beginning_of_day)
        .order(:effective_from)
    end

    def rate_phases
      SubscriptionRateCards::ResolveRatePhasesService.call!(
        subscription_rate_card:,
        plan_rate_cards:
      ).rate_phases
    end

    def plan_rate_cards
      subscription.plan.applied_rate_cards.to_a
    end

    def dates_options
      BillingPeriods::DatesService::Options.new(
        timezone: subscription.customer.applicable_timezone,
        exclude_out_of_range: true,
        realign_billing_anchor: true,
        termination: true
      )
    end

    def arrears?
      subscription_rate_card.rate_card.arrears?
    end
  end
end
