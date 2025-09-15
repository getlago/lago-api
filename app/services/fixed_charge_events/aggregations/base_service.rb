# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class BaseService < BaseService
      def initialize(fixed_charge:, subscription:, charges_from_datetime:, charges_to_datetime:)
        @fixed_charge = fixed_charge
        @subscription = subscription
        @from_datetime = charges_from_datetime
        # NOTE: we add 1 day to the duration to include the last day of the period
        @to_datetime = charges_to_datetime + 1.day
        @customer = subscription.customer
      end

      def call
        raise NotImplementedError
      end

      private

      attr_reader :fixed_charge, :subscription, :from_datetime, :to_datetime, :customer

      def base_events
        @events ||= FixedChargeEvent.where(fixed_charge:, subscription:)
      end

      def events_in_range
        @events_in_range ||= begin
          events_in_period_ids = base_events.where(timestamp: from_datetime..to_datetime).ids
          last_event_before_range_id = base_events.where("timestamp < ?", from_datetime).order(timestamp: :desc).limit(1).ids

          # Combine using UNION
          FixedChargeEvent.where(id: events_in_period_ids + last_event_before_range_id)
            .order(timestamp: :asc)
        end
      end

      def charges_duration
        @charges_duration ||= (to_datetime.to_date - from_datetime.to_date)
      end
    end
  end
end
