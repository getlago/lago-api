# frozen_string_literal: true

module Events
  module Stores
    # Aggregates the filters of a charge in a few reads of its events, one per batch of filters.
    #
    # Each filter's store reads the whole window of the subscription and the code to keep the
    # events its filter matches, so a charge with N filters read the same rows N+1 times. Here
    # every event is attributed to the filters of a batch in the same pass, with the conditions
    # the filter stores apply (ClickhouseStore#filters_condition_sql), and the rows are grouped by
    # filter.
    #
    # An event matching several filters counts in each of them, as it does in the filter stores:
    # the attribution is an ARRAY JOIN over the matching filters, not an exclusive multiIf.
    #
    # The groups are the union of the pricing group keys of every filter, and each filter's store
    # sums the rows back to its own keys, which count and sum allow.
    class ChargeFiltersScan
      SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

      # Every filter adds its condition to the query and to the work done on each event, so
      # filters are read in batches: a query stays the size of the filter stores' ones, however
      # many filters the charge holds, and only the batches holding a filter to aggregate are read.
      FILTERS_PER_SCAN = 100

      # The default filter is not persisted: it has no id to attribute its events to.
      DEFAULT_FILTER_KEY = "default"

      Bucket = Data.define(:key, :matching_filters, :ignored_filters)
      Row = Data.define(:groups, :value, :events_count)

      def self.supported_charge?(charge)
        return false if charge.nil?

        SUPPORTED_AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type) &&
          !charge.prorated? &&
          charge.filters.size.positive?
      end

      def initialize(charge:)
        @charge = charge
        @buckets = {}
        @rows = {}
      end

      # Only the calls the filter's own store would answer the same way: the scan is built from
      # the charge, so a store whose conditions were changed by its caller (a group filter on the
      # usage for instance) or which groups by a key the scan does not read keeps its own query.
      def covers?(store)
        key = filter_key(store.charge_filter_id)
        return false unless batch_index.key?(key)

        bucket = bucket(key)

        bucket.matching_filters == store.matching_filters &&
          bucket.ignored_filters == store.ignored_filters &&
          (store.grouped_by || []).all? { group_keys.include?(it) }
      end

      def count(store)
        events_count = rows_for(store).sum(0, &:events_count)

        BaseStore::AggregationResult.new(value: events_count, events_count:)
      end

      def sum(store, with_count: true)
        rows = rows_for(store)

        BaseStore::AggregationResult.new(
          value: rows.sum(BigDecimal(0), &:value),
          events_count: (rows.sum(0, &:events_count) if with_count)
        )
      end

      # Mirrors ClickhouseStore#grouped_count, which returns the count as a decimal value and
      # reuses it as the events count.
      def grouped_count(store)
        grouped_rows_for(store).map do |groups, rows|
          value = BigDecimal(rows.sum(0, &:events_count))

          BaseStore::GroupedAggregationResult.new(groups:, value:, events_count: value)
        end
      end

      def grouped_sum(store, with_count: true)
        grouped_rows_for(store).map do |groups, rows|
          BaseStore::GroupedAggregationResult.new(
            groups:,
            value: rows.sum(BigDecimal(0), &:value),
            events_count: (rows.sum(0, &:events_count) if with_count)
          )
        end
      end

      private

      attr_reader :charge

      def filter_key(charge_filter_id)
        charge_filter_id || DEFAULT_FILTER_KEY
      end

      # The pricing buckets Fees::ChargeService computes the charge fees for, keyed by filter.
      def pricing_buckets
        @pricing_buckets ||= Fees::ChargeService::Sources::Charge.new(charge:, boundaries: nil)
          .pricing_buckets
          .index_by { filter_key(it.charge_filter&.id) }
      end

      def batch_index
        @batch_index ||= pricing_buckets.keys.each_slice(FILTERS_PER_SCAN).with_index.each_with_object({}) do |(keys, index), acc|
          keys.each { acc[it] = index }
        end
      end

      def batch_keys(index)
        pricing_buckets.keys.slice(index * FILTERS_PER_SCAN, FILTERS_PER_SCAN)
      end

      # The conditions Fees::ChargeService gives the filter's store. Resolved per filter, as a
      # charge holding thousands of filters only reads the batches of those it aggregates.
      def bucket(key)
        @buckets[key] ||= begin
          matching_and_ignored = pricing_buckets.fetch(key).matching_and_ignored_filters

          Bucket.new(
            key:,
            matching_filters: matching_and_ignored.matching_filters,
            ignored_filters: matching_and_ignored.ignored_filters
          )
        end
      end

      def group_keys
        @group_keys ||= pricing_buckets.values.flat_map(&:pricing_group_keys).uniq
      end

      def rows_for(store)
        key = filter_key(store.charge_filter_id)

        scan(store, batch_index.fetch(key)).fetch(key, [])
      end

      def grouped_rows_for(store)
        columns = store.grouped_by

        rows_for(store)
          .group_by { |row| columns.index_with { row.groups[it].presence } }
          .to_a
      end

      # One read per batch and window: the stores of the batch share it, and recurring metrics
      # read theirs without the lower boundary.
      def scan(store, batch)
        from_datetime = (store.from_datetime if store.use_from_boundary)
        key = [batch, from_datetime, store.applicable_to_datetime, store.deduplicate]

        @rows[key] ||= Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          connection
            .select_all(scan_sql(store, batch:, from_datetime:))
            .rows
            .each_with_object({}) do |(position, *groups, value, events_count), acc|
              filter_key = batch_keys(batch).fetch(position.to_i - 1)

              (acc[filter_key] ||= []) << Row.new(
                groups: group_keys.zip(groups).to_h,
                value: BigDecimal((value || 0).to_s),
                events_count: events_count.to_i
              )
            end
        end
      end

      def scan_sql(store, batch:, from_datetime:)
        to_datetime = store.applicable_to_datetime

        events_sql = if store.deduplicate
          store.deduplicated_events_sql(from_datetime:, to_datetime:, deduplicated_columns: %w[decimal_value properties])
        else
          <<~SQL.squish
            SELECT decimal_value, properties
            FROM events_enriched
            WHERE #{store.deduplicated_events_where_sql(from_datetime:, to_datetime:)}
          SQL
        end

        group_columns = group_keys.map.with_index do |key, index|
          "#{store.sanitized_property_name(key)} AS g_#{index}"
        end
        group_names = Array.new(group_keys.size) { "g_#{it}" }

        <<~SQL.squish
          SELECT
            #{["filter_position", *group_columns].join(", ")},
            sum(events_enriched.decimal_value),
            count()
          FROM (#{events_sql}) AS events_enriched
          ARRAY JOIN #{filter_positions_sql(store, batch)} AS filter_position
          GROUP BY #{["filter_position", *group_names].join(", ")}
        SQL
      end

      # The positions in the batch of the filters an event counts in. An event none of them keeps
      # is dropped by the ARRAY JOIN, as it is by each of their stores. Positions rather than the
      # filter ids: the array is built for every event, and a small integer per filter keeps it far
      # lighter than a copy of each id.
      def filter_positions_sql(store, batch)
        attributions = batch_keys(batch).map.with_index(1) do |key, position|
          bucket = bucket(key)
          condition = store.filters_condition_sql(
            matching_filters: bucket.matching_filters,
            ignored_filters: bucket.ignored_filters
          )

          "if(#{condition}, #{position}, 0)"
        end

        "arrayFilter(x -> x > 0, [#{attributions.join(", ")}])"
      end
    end
  end
end
