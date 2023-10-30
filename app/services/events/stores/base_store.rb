# frozen_string_literal: true

module Events
  module Stores
    class BaseStore
      def initialize(code:, subscription:, boundaries:, group: nil, event: nil)
        @code = code
        @subscription = subscription
        @boundaries = boundaries
        @group = group
        @event = event
      end

      def events
        raise NotImplementedError
      end

      def count
        events.count # rubocop:disable Rails/Delegate
      end

      protected

      attr_accessor :code, :subscription, :group, :event, :boundaries

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end
    end
  end
end
