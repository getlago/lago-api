# frozen_string_literal: true

module SubscriptionProductItems
  # Terminates a single product item: sets ended_at (stops the clock) and, for arrears
  # items, emits a final billing cycle for the still-open period clamped to the
  # termination instant. ComputeFeeService prorates that partial cycle, so the
  # processor turns it into the prorated final invoice.
  #
  # No-back-bill applies: the open period starts at the current boundary (never before
  # the item start), so a backdated subscription terminated today bills only the
  # current partial period, not the whole elapsed time.
  #
  # Advance items are already paid for the current period, so no final cycle.
  class TerminateService < BaseService
    Result = BaseResult[:subscription_product_item, :billing_cycle]

    def initialize(subscription_product_item:, terminated_at: Time.current)
      @subscription_product_item = subscription_product_item
      @terminated_at = terminated_at
      super
    end

    def call
      return result.not_found_failure!(resource: "subscription_product_item") unless subscription_product_item
      return result if subscription_product_item.ended_at.present?

      ActiveRecord::Base.transaction do
        result.billing_cycle = final_cycle
        subscription_product_item.update!(ended_at: terminated_at)
      end

      result.subscription_product_item = subscription_product_item
      result
    end

    private

    attr_reader :subscription_product_item, :terminated_at

    delegate :organization, :subscription, to: :subscription_product_item

    def final_cycle
      return unless rate&.rate_card&.billing_timing == "arrears"
      return if terminated_at <= period_start

      BillingCycle.create!(
        organization:,
        subscription:,
        subscription_product_item:,
        billing_at: terminated_at,
        period_from: period_start,
        period_to: terminated_at.in_time_zone(timezone).end_of_day.utc
      )
    end

    # Start of the open period the termination falls in, never before the item start.
    def period_start
      @period_start ||= [
        boundaries.at(boundaries.index_on_or_before(terminated_at.in_time_zone(timezone))),
        subscription_product_item.started_at.in_time_zone(timezone).beginning_of_day
      ].max.utc
    end

    def boundaries
      @boundaries ||= BillingPeriods::Boundaries.new(
        billing_anchor_date: subscription_product_item.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        timezone:
      )
    end

    def rate
      @rate ||= ResolveRateService.call(subscription_product_item:, datetime: terminated_at).rate
    end

    def timezone
      @timezone ||= subscription.customer.applicable_timezone
    end
  end
end
