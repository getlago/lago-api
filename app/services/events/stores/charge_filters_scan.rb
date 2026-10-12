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
    # An event counts in every filter of the batch whose conditions it meets, as it does in the
    # filter stores: the attribution is an ARRAY JOIN over the matching filters, not an exclusive
    # multiIf, and it is the ignored filters of each condition that bill an event on one filter.
    #
    # Only the filters the billing period pre-filter found events for are read, when the caller
    # gives them: on a charge with thousands of filters, few of them see usage in a period, and
    # attributing every event to the others would cost far more than their own queries, which are
    # never run.
    #
    # The groups are the union of the pricing group keys of every filter, and each filter's store
    # combines the rows back to its own keys, which count, sum, max and latest allow: a sum of
    # sums, a max of maxes, the latest of the latest values.
    class ChargeFiltersScan
      SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

      # Only read with the incremental cache, so that the organizations reading the charges with
      # filters in one scan keep their max and latest charges on the filter stores.
      INCREMENTAL_AGGREGATION_TYPES = %w[count_agg sum_agg max_agg latest_agg].freeze

      # The store calls each aggregation type is answered for. The rows of a charge hold the value
      # its aggregation needs, a max for a max charge, so they answer no other.
      OPERATIONS = {
        "count_agg" => %i[count sum],
        "sum_agg" => %i[count sum],
        "max_agg" => %i[count max],
        "latest_agg" => %i[count last]
      }.freeze

      # Every filter adds its condition to the query and to the work done on each event, so
      # filters are read in batches: a query stays the size of the filter stores' ones, however
      # many filters the charge holds, and only the batches holding a filter to aggregate are read.
      FILTERS_PER_SCAN = 100

      # The default filter is not persisted: it has no id to attribute its events to.
      DEFAULT_FILTER_KEY = "default"

      Bucket = Data.define(:key, :matching_filters, :ignored_filters)

      # The aggregates of a filter's events sharing the same groups. `value` is the sum of their
      # values, or their max, or the value of the latest of them, which `timestamp` (epoch
      # milliseconds) dates. A max or a latest value is nil when the events have none.
      Row = Data.define(:groups, :value, :events_count, :timestamp) do
        def initialize(groups:, value:, events_count:, timestamp: nil)
          super
        end
      end

      # A charge without filters only has the default bucket, which its own store reads as cheaply.
      # The scan only takes one when it keeps its rows between computations (see IncrementalCache).
      def self.supported_charge?(charge, incremental: false)
        return false if charge.nil?

        types = incremental ? INCREMENTAL_AGGREGATION_TYPES : SUPPORTED_AGGREGATION_TYPES

        types.include?(charge.billable_metric.aggregation_type) &&
          !charge.prorated? &&
          (incremental || charge.filters.size.positive?)
      end

      # The rows of the same groups read apart (in batches or windows) as one.
      def self.combine(aggregation_type, groups, rows)
        events_count = rows.sum(0, &:events_count)

        case aggregation_type
        when "max_agg"
          Row.new(groups:, value: rows.filter_map(&:value).max, events_count:)
        when "latest_agg"
          latest = rows.max_by(&:timestamp)
          Row.new(groups:, value: latest&.value, events_count:, timestamp: latest&.timestamp)
        else
          Row.new(groups:, value: rows.sum(BigDecimal(0), &:value), events_count:)
        end
      end

      # `filter_ids` are the filters to aggregate, `nil` standing for the default bucket as in the
      # pre-filter. Without them every filter of the charge is read.
      #
      # With an `incremental` cache, the events older than its cut are answered from the rows it
      # kept and only the most recent ones are read (see IncrementalCache).
      def initialize(charge:, filter_ids: nil, incremental: nil)
        @charge = charge
        @filter_keys = filter_ids&.to_set { filter_key(it) }
        @incremental = incremental
        @buckets = {}
        @rows = {}
      end

      # Only the calls the filter's own store would answer the same way: the scan is built from
      # the charge, so a store whose conditions were changed by its caller (a group filter on the
      # usage for instance) or which groups by a key the scan does not read keeps its own query.
      def covers?(store, operation = :count)
        return false unless OPERATIONS.fetch(aggregation_type, []).include?(operation)

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

      # Mirrors ClickhouseStore#max, which answers 0 without a value.
      def max(store, with_count: true)
        row = self.class.combine(aggregation_type, {}, rows_for(store))

        BaseStore::AggregationResult.new(value: row.value || 0, events_count: (row.events_count if with_count))
      end

      def grouped_max(store, with_count: true)
        grouped_rows(store, with_count:)
      end

      # Mirrors ClickhouseStore#last, which keeps a missing value nil.
      def last(store, with_count: true)
        row = self.class.combine(aggregation_type, {}, rows_for(store))

        BaseStore::AggregationResult.new(value: row.value, events_count: (row.events_count if with_count))
      end

      def grouped_last(store, with_count: true)
        grouped_rows(store, with_count:)
      end

      private

      attr_reader :charge, :filter_keys, :incremental

      def aggregation_type
        charge.billable_metric.aggregation_type
      end

      def grouped_rows(store, with_count: true)
        grouped_rows_for(store).map do |groups, rows|
          row = self.class.combine(aggregation_type, groups, rows)

          BaseStore::GroupedAggregationResult.new(
            groups:,
            value: row.value,
            events_count: (row.events_count if with_count)
          )
        end
      end

      def filter_key(charge_filter_id)
        charge_filter_id || DEFAULT_FILTER_KEY
      end

      # The pricing buckets Fees::ChargeService computes the charge fees for, keyed by filter, down
      # to the ones to aggregate. The conditions of those still ignore the events of every filter
      # they rank behind, aggregated or not.
      def pricing_buckets
        @pricing_buckets ||= begin
          buckets = Fees::ChargeService::Sources::Charge.new(charge:, boundaries: nil)
            .pricing_buckets
            .index_by { filter_key(it.charge_filter&.id) }

          filter_keys ? buckets.slice(*filter_keys) : buckets
        end
      end

      def batch_index
        @batch_index ||= pricing_buckets.keys.each_slice(FILTERS_PER_SCAN).with_index.each_with_object({}) do |(keys, index), acc|
          keys.each { acc[it] = index }
        end
      end

      def batch_keys(index)
        pricing_buckets.keys.slice(index * FILTERS_PER_SCAN, FILTERS_PER_SCAN)
      end

      # What decides which events each filter of the batch keeps, as the scan reads it.
      def batch_conditions(index)
        batch_keys(index).map do |key|
          bucket = bucket(key)

          [key, bucket.matching_filters, bucket.ignored_filters]
        end
      end

      # The conditions Fees::ChargeService gives the filter's store. Resolved per filter, as a
      # charge holding thousands of filters only reads the batches of those it aggregates.
      #
      # A charge without filters has no conditions, as its store has none.
      def bucket(key)
        @buckets[key] ||= if charge.filters.empty?
          Bucket.new(key:, matching_filters: {}, ignored_filters: [])
        else
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
        to_datetime = store.applicable_to_datetime
        key = [batch, from_datetime, to_datetime, store.deduplicate]

        @rows[key] ||= if incremental
          incremental.rows(
            store:,
            from_datetime:,
            to_datetime:,
            conditions: batch_conditions(batch),
            group_keys:
          ) { |**window| read_rows(store, batch, **window) }
        else
          read_rows(store, batch, from_datetime:, to_datetime:)
        end
      end

      # The rows of the batch's filters for the events of `from_datetime` (included) to
      # `to_datetime` (included) or `before` (excluded).
      def read_rows(store, batch, from_datetime:, to_datetime:, before: nil)
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          connection
            .select_all(scan_sql(store, batch:, from_datetime:, to_datetime:, before:))
            .rows
            .each_with_object({}) do |(position, *columns), acc|
              filter_key = batch_keys(batch).fetch(position.to_i - 1)
              groups = columns.first(group_keys.size)
              value, events_count, timestamp = columns.drop(group_keys.size)

              (acc[filter_key] ||= []) << Row.new(
                groups: group_keys.zip(groups).to_h,
                value: row_value(value),
                events_count: events_count.to_i,
                timestamp: timestamp&.to_i
              )
            end
        end
      end

      # A sum without values is 0, as in the filter stores, while a max or a latest value stays nil.
      def row_value(value)
        if value.nil?
          (aggregation_type == "max_agg" || aggregation_type == "latest_agg") ? nil : BigDecimal(0)
        else
          BigDecimal(value.to_s)
        end
      end

      def scan_sql(store, batch:, from_datetime:, to_datetime:, before: nil)
        events_sql = if store.deduplicate
          store.deduplicated_events_sql(from_datetime:, to_datetime:, deduplicated_columns: %w[decimal_value properties], before:)
        else
          <<~SQL.squish
            SELECT #{(aggregation_type == "latest_agg") ? "decimal_value, properties, timestamp" : "decimal_value, properties"}
            FROM events_enriched
            WHERE #{store.deduplicated_events_where_sql(from_datetime:, to_datetime:, before:)}
          SQL
        end

        group_columns = group_keys.map.with_index do |key, index|
          "#{store.sanitized_property_name(key)} AS g_#{index}"
        end
        group_names = Array.new(group_keys.size) { "g_#{it}" }

        <<~SQL.squish
          SELECT
            #{["filter_position", *group_columns].join(", ")},
            #{aggregates_sql}
          FROM (#{events_sql}) AS events_enriched
          ARRAY JOIN #{filter_positions_sql(store, batch)} AS filter_position
          GROUP BY #{["filter_position", *group_names].join(", ")}
        SQL
      end

      # The value, the events count and, for the latest value, its timestamp. The value is wrapped
      # in a tuple for argMax, which would otherwise skip the events without one rather than
      # answer nil for a latest event without a value, as ClickhouseStore#last does.
      def aggregates_sql
        case aggregation_type
        when "max_agg"
          "max(events_enriched.decimal_value), count()"
        when "latest_agg"
          <<~SQL.squish
            tupleElement(argMax(tuple(events_enriched.decimal_value), events_enriched.timestamp), 1),
            count(),
            toUnixTimestamp64Milli(max(events_enriched.timestamp))
          SQL
        else
          "sum(events_enriched.decimal_value), count()"
        end
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
