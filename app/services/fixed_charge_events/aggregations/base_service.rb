# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class BaseService < BaseService
      Result = BaseResult[:count, :aggregation, :current_usage_units, :full_units_number, :total_aggregated_units]

      def initialize(fixed_charge:, subscription:, boundaries:)
        @fixed_charge = fixed_charge
        @subscription = subscription
        @customer = subscription.customer
        # TODO: switch to fixed_charges_boundaries
        @from_datetime = boundaries.fixed_charges_from_datetime
        @to_datetime = boundaries.fixed_charges_to_datetime
        @charges_duration = boundaries.fixed_charges_duration

        super(nil)
      end

      def call
        raise NotImplementedError
      end

      private

      attr_reader :fixed_charge, :subscription, :from_datetime, :to_datetime, :customer, :charges_duration

      def base_events
        @events ||= FixedChargeEvent.where(fixed_charge:, subscription:)
      end

      def events_in_range
        @events_in_range ||= begin
          events_in_period_ids = base_events.where("timestamp >= ? AND timestamp < ?", from_datetime, to_datetime).ids
          last_event_before_range_id = base_events.where("created_at < ?", from_datetime).where("timestamp < ?", from_datetime).order(created_at: :desc).limit(1).ids

          FixedChargeEvent.where(id: events_in_period_ids + last_event_before_range_id)
            .order(created_at: :asc)
        end
      end
    end
  end
end
