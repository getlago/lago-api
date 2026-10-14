# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    # Keeps the pre-filter answer of a window up to date by reading only the events ingested since
    # it was last computed, instead of every event of the window on each call.
    #
    # The pre-filter decides which charge filters are aggregated and feeds the charge cache with
    # the last ingestion time of each combination. A combination it misses leaves the usage of its
    # filters out, while one it returns in excess only costs an aggregation that finds nothing.
    # Every choice here therefore errs towards a superset:
    #
    # - the window read again starts INGESTION_MARGIN before the previous read started, so rows
    #   stamped before that read but committed after it are read on the next one. Reading a row
    #   twice is harmless, as merging keeps one combination and its latest ingestion time;
    # - a combination is never removed by a later read. The events behind it can be replaced or
    #   deleted, so the answer is computed from scratch again every FULL_REFRESH_INTERVAL.
    class IncrementalCombinations
      CACHE_KEY_VERSION = "1"

      # The ingestion time is stamped when a row is inserted, which can be some time before
      # readers see it.
      INGESTION_MARGIN = 5.minutes

      # How long a combination of a replaced or deleted event can outlive it.
      FULL_REFRESH_INTERVAL = 6.hours

      # An answer this large is not kept: reading it back would cost more than it saves.
      MAX_COMBINATIONS = 10_000

      Entry = Data.define(:combinations, :read_at, :full_read_at)

      def initialize(cache_key:)
        @cache_key = cache_key
      end

      # Yields `ingested_after:`, nil asking for every event of the window, and expects the
      # combinations of the events store: [code, properties, last_seen_at] rows.
      def fetch
        read_at = Time.current
        entry = read_entry

        if entry && read_at - entry.full_read_at < FULL_REFRESH_INTERVAL
          combinations = merge(entry.combinations, yield(ingested_after: entry.read_at - INGESTION_MARGIN))
          write_entry(Entry.new(combinations:, read_at:, full_read_at: entry.full_read_at))
        else
          combinations = yield(ingested_after: nil)
          write_entry(Entry.new(combinations:, read_at:, full_read_at: read_at))
        end

        combinations
      end

      private

      attr_reader :cache_key

      def read_entry
        attributes = Rails.cache.read(cache_key)
        Entry.new(**attributes) if attributes
      end

      # Concurrent reads of the same window each write what they read: the last write wins and
      # carries the start time of its own read, so the next read covers anything the others saw.
      def write_entry(entry)
        if entry.combinations.size > MAX_COMBINATIONS
          Rails.cache.delete(cache_key)
        else
          Rails.cache.write(cache_key, entry.to_h, expires_in: FULL_REFRESH_INTERVAL)
        end
      end

      def merge(combinations, new_combinations)
        merged = combinations.index_by { |(code, properties, _)| [code, properties] }

        new_combinations.each do |(code, properties, last_seen_at)|
          key = [code, properties]
          current = merged[key]

          if current.nil? || (last_seen_at && (current.last.nil? || last_seen_at > current.last))
            merged[key] = [code, properties, last_seen_at]
          end
        end

        merged.values
      end
    end
  end
end
