# frozen_string_literal: true

module Events
  module Stores
    # Answers a charge filter's count, sum, recurring sum, max and latest value from the read of every filter of
    # its charge, and delegates the rest to the store it wraps, which also answers whatever the read does not
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
        if scanned?(operation: :count)
          scan.count(__getobj__)
        else
          super
        end
      end

      def sum(with_count: true)
        if scanned?(operation: :sum)
          scan.sum(__getobj__, with_count:)
        else
          super
        end
      end

      # Other columns are a presentation breakdown, which keeps its own query.
      def grouped_count(columns = grouped_by)
        if scanned?(columns, operation: :count)
          scan.grouped_count(__getobj__)
        else
          super
        end
      end

      def grouped_sum(columns = grouped_by, with_count: true)
        if scanned?(columns, operation: :sum)
          scan.grouped_sum(__getobj__, with_count:)
        else
          super
        end
      end

      # The delta of a closed period keeps the store's own read, pruned by timestamp and enriched_at.
      def recurring_sum(watermark:, period: nil)
        if period.nil? && scanned?(operation: :recurring_sum)
          scan.recurring_sum(__getobj__, watermark:)
        else
          super
        end
      end

      def grouped_recurring_sum(watermark:, period: nil)
        if period.nil? && scanned?(operation: :recurring_sum)
          scan.grouped_recurring_sum(__getobj__, watermark:)
        else
          super
        end
      end

      def max(with_count: true)
        if scanned?(operation: :max)
          scan.max(__getobj__, with_count:)
        else
          super
        end
      end

      def grouped_max(columns = grouped_by, with_count: true)
        if scanned?(columns, operation: :max)
          scan.grouped_max(__getobj__, with_count:)
        else
          super
        end
      end

      def last(with_count: true)
        if scanned?(operation: :last)
          scan.last(__getobj__, with_count:)
        else
          super
        end
      end

      def grouped_last(columns = grouped_by, with_count: true)
        if scanned?(columns, operation: :last)
          scan.grouped_last(__getobj__, with_count:)
        else
          super
        end
      end

      private

      attr_reader :scan

      # Asked on each call: a running total narrows the store to one group for the duration of
      # a block (BaseStore#with_grouped_by_values), which the read of the whole charge ignores.
      def scanned?(columns = grouped_by, operation:)
        columns == grouped_by && !grouped_by_values? && scan.covers?(__getobj__, operation)
      end
    end
  end
end
