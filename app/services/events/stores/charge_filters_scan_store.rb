# frozen_string_literal: true

module Events
  module Stores
    # Answers a charge filter's count and sum from the read of every filter of its charge, and
    # delegates the rest to the store it wraps, which also answers whatever the read does not
    # cover (see ChargeFiltersScan#covers?).
    #
    # Unlike UsageBucketStore it is not precomputed: it aggregates the same events as the store
    # it wraps, so its fees go through the charge cache like the store's.
    class ChargeFiltersScanStore < SimpleDelegator
      def initialize(store, scan:)
        @scan = scan

        super(store)
      end

      def count
        if scanned?
          scan.count(__getobj__)
        else
          super
        end
      end

      def sum(with_count: true)
        if scanned?
          scan.sum(__getobj__, with_count:)
        else
          super
        end
      end

      # Other columns are a presentation breakdown, which keeps its own query.
      def grouped_count(columns = grouped_by)
        if scanned?(columns)
          scan.grouped_count(__getobj__)
        else
          super
        end
      end

      def grouped_sum(columns = grouped_by, with_count: true)
        if scanned?(columns)
          scan.grouped_sum(__getobj__, with_count:)
        else
          super
        end
      end

      private

      attr_reader :scan

      # Asked on each call: a running total narrows the store to one group for the duration of
      # a block (BaseStore#with_grouped_by_values), which the read of the whole charge ignores.
      def scanned?(columns = grouped_by)
        columns == grouped_by && !grouped_by_values? && scan.covers?(__getobj__)
      end
    end
  end
end
