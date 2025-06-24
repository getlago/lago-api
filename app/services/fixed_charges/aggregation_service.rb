# frozen_string_literal: true

module FixedCharges
  class AggregationService < BaseService
    Result = BaseResult[
      :aggregation, # Total units from events
      :current_usage_units, # Units for current usage
      :full_units_number, # Total units ignoring proration
      :count, # Number of events
      :total_aggregated_units # Total aggregated units
    ]

    def initialize(fixed_charge:, subscription:, boundaries:)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)

      super
    end

    def call
      events = fetch_fixed_charge_events

      result.aggregation = events.sum { |event| BigDecimal(event.properties["units"].to_s) }
      result.current_usage_units = result.aggregation
      result.full_units_number = result.aggregation
      result.count = events.count
      result.total_aggregated_units = result.aggregation

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :boundaries

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
  end
end
