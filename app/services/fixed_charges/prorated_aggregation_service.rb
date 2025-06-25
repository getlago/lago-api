# frozen_string_literal: true

module FixedCharges
  class ProratedAggregationService < BaseService
    Result = BaseResult[
      :aggregation, # Total units from events (prorated)
      :current_usage_units, # Units for current usage
      :full_units_number, # Total units ignoring proration
      :count, # Number of events
      :total_aggregated_units, # Total aggregated units
      :full_period_days # Number of days in the period
    ]

    def initialize(fixed_charge:, subscription:, boundaries:)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)

      super
    end

    def call
      events = fetch_fixed_charge_events
      full_units = events.sum { |event| BigDecimal(event.properties["units"].to_s) }

      result.full_units_number = full_units
      result.current_usage_units = full_units
      result.count = events.count
      result.total_aggregated_units = full_units
      result.full_period_days = full_period_days

      if fixed_charge.prorated?
        # For prorated fixed charges, calculate the prorated units
        # based on the subscription period vs full billing period
        proration_coefficient = calculate_proration_coefficient
        result.aggregation = (full_units * proration_coefficient).ceil(5)
      else
        # For non-prorated fixed charges, use the full units
        result.aggregation = full_units
      end

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :boundaries

    delegate :plan, to: :fixed_charge

    def fetch_fixed_charge_events
      Event.where(
        organization: subscription.organization,
        external_subscription_id: subscription.external_id,
        code: fixed_charge.add_on.code,
        source: Event.sources[:fixed_charge]
      ).where(
        "timestamp >= ? AND timestamp <= ?",
        boundaries.charges_from_datetime,
        boundaries.charges_to_datetime
      ).where(
        "metadata->>'fixed_charge_id' = ?",
        fixed_charge.id.to_s
      ).order(:timestamp)
    end

    def calculate_proration_coefficient
      # Number of days in the subscription period
      subscription_days = subscription.date_diff_with_timezone(
        boundaries.charges_from_datetime,
        boundaries.charges_to_datetime
      )

      # Number of days in the full billing period
      full_period_days = full_period_days

      # Proration coefficient = subscription_days / full_period_days
      subscription_days.fdiv(full_period_days)
    end

    def full_period_days
      # Calculate the real number of days in the billing period
      # based on the subscription's billing cycle
      case plan.interval
      when "monthly"
        # Calculate days from the start of the billing period to the start of the next billing period
        billing_start = subscription.started_at.beginning_of_month.to_date
        billing_end = billing_start.next_month.to_date
        (billing_end - billing_start).to_i
      when "yearly"
        # Calculate days from the start of the billing period to the start of the next billing period
        billing_start = subscription.started_at.beginning_of_year.to_date
        billing_end = billing_start.next_year.to_date
        (billing_end - billing_start).to_i
      when "weekly"
        7 # a week always has 7 days
      when "quarterly"
        # Calculate days from the start of the billing period to the start of the next billing period
        billing_start = subscription.started_at.beginning_of_quarter.to_date
        billing_end = billing_start.next_quarter.to_date
        (billing_end - billing_start).to_i
      else
        raise "Unsupported interval: #{plan.interval}"
      end
    end
  end
end
