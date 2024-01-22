# frozen_string_literal: true

module Events
  module Stores
    class BaseStore
      def initialize(code:, subscription:, boundaries:, filters: {})
        @code = code
        @subscription = subscription
        @boundaries = boundaries

        @group = filters[:group]
        @grouped_by = filters[:grouped_by]
        @grouped_by_value = filters[:grouped_by_value]

        @aggregation_property = nil
        @numeric_property = false
        @use_from_boundary = true
      end

      def grouped_by_value?
        grouped_by.present? && grouped_by_value.present?
      end

      def events(force_from: false)
        raise NotImplementedError
      end

      def events_values(limit: nil, force_from: false)
        raise NotImplementedError
      end

      def last_event
        raise NotImplementedError
      end

      def prorated_events_values(total_duration)
        raise NotImplementedError
      end

      delegate :count, to: :events

      def max
        raise NotImplementedError
      end

      def last
        raise NotImplementedError
      end

      def sum
        raise NotImplementedError
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        raise NotImplementedError
      end

      # NOTE: returns the breakdown of the sum grouped by date
      #       The result format will be an array of hash with the format:
      #       [{ date: Date.parse('2023-11-27'), value: 12.9 }, ...]
      def sum_date_breakdown
        raise NotImplementedError
      end

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end

      def charges_duration
        boundaries[:charges_duration]
      end

      attr_accessor :numeric_property, :aggregation_property, :use_from_boundary

      protected

      attr_accessor :code, :subscription, :group, :boundaries, :grouped_by, :grouped_by_value

      delegate :customer, to: :subscription

      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(
          subscription,
          to_datetime + 1.day,
          current_usage: subscription.terminated? && subscription.upgraded?,
        ).charges_duration_in_days
      end
    end
  end
end
