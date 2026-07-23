# frozen_string_literal: true

module SubscriptionRateCards
  # Terminates a single product item: sets ended_at (stops the clock) and, for arrears
  # items, emits a final billing cycle for the still-open period clamped to the
  # termination instant. ComputeFeeService prorates that partial cycle, so the
  # processor turns it into the prorated final invoice.
  #
  # No-back-bill applies: the open period starts at the current boundary (never before
  # the item start), so a backdated subscription terminated today bills only the
  # current partial period, not the whole elapsed time.
  #
  # Advance items are already paid for the current period, so they get no final cycle;
  # the paid-but-unused remainder is credited at the subscription level after all items
  # are ended (V2::Subscriptions::CreditUnusedAdvanceService), so items sharing an
  # invoice collapse into a single credit note.
  class TerminateService < BaseService
    Result = BaseResult[:subscription_rate_card, :billing_cycle]

    def initialize(subscription_rate_card:, terminated_at: Time.current)
      @subscription_rate_card = subscription_rate_card
      @terminated_at = terminated_at
      super
    end

    def call
      return result.not_found_failure!(resource: "subscription_rate_card") unless subscription_rate_card
      return result if subscription_rate_card.ended_at.present?

      ActiveRecord::Base.transaction do
        result.billing_cycle = final_cycle
        subscription_rate_card.update!(ended_at: terminated_at)
      end

      result.subscription_rate_card = subscription_rate_card
      result
    end

    private

    attr_reader :subscription_rate_card, :terminated_at

    delegate :organization, :subscription, :customer, to: :subscription_rate_card

    def final_cycle
      return unless rate&.rate_card&.billing_timing == "arrears"
      return if terminated_at <= period_start

      BillingCycle.create!(
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        billing_at: terminated_at,
        period_from: period_start,
        period_to: terminated_at.utc
      )
    end

    # Start of the open period the termination falls in, never before the item start.
    def period_start
      @period_start ||= [
        boundaries.at(boundaries.index_on_or_before(terminated_at.in_time_zone(timezone))),
        subscription_rate_card.started_at.in_time_zone(timezone).beginning_of_day
      ].max.utc
    end

    def boundaries
      @boundaries ||= BillingPeriods::Boundaries.new(
        billing_anchor_date: subscription_rate_card.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        timezone:
      )
    end

    def rate
      @rate ||= ResolveRateService.call(subscription_rate_card:, datetime: terminated_at).rate
    end

    def timezone
      @timezone ||= subscription.customer.applicable_timezone
    end
  end
end
