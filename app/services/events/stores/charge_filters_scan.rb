# frozen_string_literal: true

module Events
  module Stores
    # Aggregates every filter of a charge in a single read of its events.
    #
    # Each filter's store reads the whole window of the subscription and the code to keep the
    # events its filter matches, so a charge with N filters read the same rows N+1 times. Here
    # every event is attributed to its filters in the same pass, with the conditions the filter
    # stores apply (ClickhouseStore#filters_condition_sql), and the rows are grouped by filter.
    #
    # An event matching several filters counts in each of them, as it does in the filter stores:
    # the attribution is an ARRAY JOIN over the matching filters, not an exclusive multiIf.
    #
    # The groups are the union of the pricing group keys of every filter, and each filter's store
    # sums the rows back to its own keys, which count and sum allow.
    class ChargeFiltersScan
      SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

      # Beyond it the conditions grow the query towards the ClickHouse max_query_size, and the
      # filter stores remain the safer path.
      MAX_FILTERS = 100

      # The default filter is not persisted: it has no id to attribute its events to.
      DEFAULT_FILTER_KEY = "default"

      Bucket = Data.define(:key, :matching_filters, :ignored_filters)
      Row = Data.define(:groups, :value, :events_count)

      def self.supported_charge?(charge)
        return false if charge.nil?

        SUPPORTED_AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type) &&
          !charge.prorated? &&
          charge.filters.size.between?(1, MAX_FILTERS)
      end

      def initialize(charge:)
        @charge = charge
        @rows = {}
      end

      # Only the calls the filter's own store would answer the same way: the scan is built from
      # the charge, so a store whose conditions were changed by its caller (a group filter on the
      # usage for instance) or which groups by a key the scan does not read keeps its own query.
      def covers?(store)
        bucket = buckets[filter_key(store.charge_filter_id)]
        return false if bucket.nil?

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

      # The pricing buckets Fees::ChargeService computes the charge fees for, with the conditions
      # it gives their stores.
      def buckets
        @buckets ||= pricing_buckets.to_h do |item|
          matching_and_ignored = item.matching_and_ignored_filters

          bucket = Bucket.new(
            key: filter_key(item.charge_filter&.id),
            matching_filters: matching_and_ignored.matching_filters,
            ignored_filters: matching_and_ignored.ignored_filters
          )

          [bucket.key, bucket]
        end
      end

      def group_keys
        @group_keys ||= pricing_buckets.flat_map(&:pricing_group_keys).uniq
      end

      def pricing_buckets
        @pricing_buckets ||= Fees::ChargeService::Sources::Charge.new(charge:, boundaries: nil).pricing_buckets
      end

      def rows_for(store)
        scan(store).fetch(filter_key(store.charge_filter_id), [])
      end

      def grouped_rows_for(store)
        columns = store.grouped_by

        rows_for(store)
          .group_by { |row| columns.index_with { row.groups[it].presence } }
          .to_a
      end

      # One read per window: the stores of a charge share it, and recurring metrics read theirs
      # without the lower boundary.
      def scan(store)
        from_datetime = (store.from_datetime if store.use_from_boundary)
        key = [from_datetime, store.applicable_to_datetime, store.deduplicate]

        @rows[key] ||= Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          connection
            .select_all(scan_sql(store, from_datetime:))
            .rows
            .each_with_object({}) do |(filter_key, *groups, value, events_count), acc|
              (acc[filter_key] ||= []) << Row.new(
                groups: group_keys.zip(groups).to_h,
                value: BigDecimal((value || 0).to_s),
                events_count: events_count.to_i
              )
            end
        end
      end

      def scan_sql(store, from_datetime:)
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
            #{["filter_key", *group_columns].join(", ")},
            sum(events_enriched.decimal_value),
            count()
          FROM (#{events_sql}) AS events_enriched
          ARRAY JOIN #{filter_keys_sql(store)} AS filter_key
          GROUP BY #{["filter_key", *group_names].join(", ")}
        SQL
      end

      # The keys of the filters an event counts in. An event no filter keeps, the default one
      # included, is dropped by the ARRAY JOIN, as it is by every filter store.
      def filter_keys_sql(store)
        attributions = buckets.values.map do |bucket|
          condition = store.filters_condition_sql(
            matching_filters: bucket.matching_filters,
            ignored_filters: bucket.ignored_filters
          )

          "if(#{condition}, #{store.quote(bucket.key)}, '')"
        end

        "arrayFilter(x -> x != '', [#{attributions.join(", ")}])"
      end
    end
  end
end
