# frozen_string_literal: true

module Subscriptions
  module Dates
    class TimebasedService < Subscriptions::DatesService
      def from_datetime
        billing_at
      end

      def to_datetime
        billing_at + block_time_in_minutes.minutes
      end

      def charges_from_datetime
        billing_at
      end

      def charges_to_datetime
        billing_at + block_time_in_minutes.minutes
      end

      private

      def block_time_in_minutes
        @block_time_in_minutes = subscription
          .plan
          .charges
          .where(charge_model: :timebased)
          .first
          .properties['block_time_in_minutes']
          .to_i
      end
    end
  end
end
