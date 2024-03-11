# frozen_string_literal: true

module Subscriptions
  module Dates
    class TimebasedService < Subscriptions::DatesService
      def from_datetime
        base_datetime
      end

      def to_datetime
        add_block_time(from_datetime)
      end

      def charges_from_datetime
        base_datetime
      end

      def charges_to_datetime
        add_block_time(charges_from_datetime)
      end

      private

      def base_datetime
        if charge_group_type == Utils::Constants::CHARGE_GROUP_TYPES[:PACKAGE_TIMEBASED_GROUP]
          latest_timebased_event.timestamp
        else
          billing_at
        end
      end

      def add_block_time(datetime)
        datetime + block_time_in_minutes.minutes
      end

      def block_time_in_minutes
        @block_time_in_minutes ||= subscription
          .plan
          .charges
          .where(charge_model: :timebased)
          .first
          .properties['block_time_in_minutes']
          .to_i
      end

      def latest_timebased_event
        @latest_timebased_event ||= Utils::TimebasedEventFinderService.new(
          subscription:,
          timestamp: billing_at,
        ).latest_timebased_event
      end

      def charge_group
        @charge_group ||= subscription
          .plan
          .charges.where(charge_model: :package_group)
          .first
          &.charge_group
      end

      def charge_group_type
        return nil unless charge_group

        @charge_group_type ||= Utils::ChargeGroupTypeDeterminerService.new(charge_group).call
      end
    end
  end
end
