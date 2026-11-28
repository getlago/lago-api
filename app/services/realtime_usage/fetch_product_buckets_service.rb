# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of a contract's billing segments from the ClickHouse product
  # buckets, in one query. Like FetchBucketsService, a failed read is a service failure that
  # leaves the caller reading events, and the read never raises.
  #
  # The set is keyed by [contract rate card id, product filter id] in place of [charge id, charge
  # filter id]: in a computation, a card prices one segment, which reads one product filter.
  #
  # A bucket row holds every product filter its events match, not the one billing them: a
  # segment ranks the filters it prices first (Sources::BillingSegment#filter_precedence), and
  # which ones it prices depends on its customer-local dates, which the pipeline does not know.
  # So each segment picks the winner of every matched set itself, as it does for an event, and
  # keeps the rows its own filter wins.
  class FetchProductBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    # A segment grouping by a key its rows were written without (a rate override, or keys
    # edited after the events) cannot be regrouped from the buckets: the events are read instead.
    class MissingGroupKeyError < StandardError; end

    # The segments the buckets can answer exactly, which the provider serves and this reads: a
    # window on bucket walls, as a bucket is summed whole. Segments start on customer-local
    # midnights and arrears rates on UTC ones, so this only rules out the unexpected.
    def self.readable_segments(billing_segments)
      billing_segments.select { |segment| on_bucket_walls?(segment) }
    end

    def self.on_bucket_walls?(segment)
      [segment.started_at, BillingSegment.exclusive_end(segment.ended_at)].all? do |time|
        RealtimeUsage.floor_to_bucket(time) == time
      end
    end

    def initialize(contract:, billing_segments:)
      @contract = contract
      @billing_segments = billing_segments

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)
      return result if read_segments.empty?

      result.usage_buckets = Events::Stores::UsageBucketSet.new(totals:, grouped_totals:)
      result
    rescue MissingGroupKeyError
      result
    rescue *READ_ERRORS => e
      Sentry.capture_exception(e)
      result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
    end

    private

    attr_reader :contract, :billing_segments

    def organization
      @organization ||= contract.organization
    end

    def read_segments
      @read_segments ||= self.class.readable_segments(billing_segments)
    end

    def windows
      @windows ||= read_segments.map { window(it) }.uniq
    end

    def segments_by_product
      @segments_by_product ||= read_segments.group_by { product_id_of(it) }
    end

    def totals
      rows.each_with_object({}) do |row, acc|
        acc[row[:key]] = combine_totals(acc[row[:key]], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[row[:key]] ||= {})
        groups[row[:groups]] = combine_totals(groups[row[:groups]], row)
      end
    end

    def combine_totals(totals, row)
      row_totals = Events::Stores::UsageBucketSet::Totals.new(
        aggregation_type: row[:aggregation_type],
        units: row[:units],
        events_count: row[:events_count],
        last_event_at: row[:last_event_at],
        precise_total_amount_cents: row[:precise_total_amount_cents]
      )

      totals ? totals.combine(row_totals) : row_totals
    end

    # One row per segment billing it: a bucket row is in the window of every segment of its
    # product flagged in in_windows, and is billed by those whose filter wins its matched set.
    def rows
      @rows ||= Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }.flat_map do |row|
        product_id, matched_filter_ids, grouped_by, aggregation_type, in_windows, sum_units, max_units, latest_units, last_event_at, events_count, precise_total_amount_cents = row
        units = {sum_units:, max_units:, latest_units:}
          .fetch(FetchBucketsService::UNITS_BY_AGGREGATION_TYPE.fetch(aggregation_type, :sum_units))
        matched_ids = matched_filter_ids.split(",")
        groups = parse_groups(grouped_by)

        segments_by_product.fetch(product_id).filter_map do |segment|
          next unless in_windows[windows.index(window(segment))] == 1
          next unless billed_by?(segment, matched_ids)

          {
            key: [segment.contract_rate_card_id, filter_id_of(segment) || ""],
            groups: expected_groups(segment, groups),
            aggregation_type:,
            units: units.to_d,
            last_event_at: last_event_at.to_time,
            events_count: events_count.to_i,
            precise_total_amount_cents: precise_total_amount_cents.to_d
          }
        end
      end
    end

    # Grouped by the windows a row falls in, so that one read serves segments of the same product
    # on different windows (cards with their own billing anchors).
    def fetch_rows
      Clickhouse::ProductUsageBucket
        .where(organization_id: organization.id, contract_id: contract.id, is_deleted: 0)
        .where(product_id: segments_by_product.keys)
        .where(bucket: windows.map(&:begin).min...windows.map(&:end).max)
        .group(:product_id, :matched_filter_ids, :grouped_by, :aggregation_type, Arel.sql(in_windows_sql))
        .pluck(Arel.sql(<<~SQL.squish))
          product_id, matched_filter_ids, grouped_by, aggregation_type, #{in_windows_sql},
          sum(units), max(units), argMax(units, last_event_at), max(last_event_at), sum(events_count),
          sum(precise_total_amount_cents)
        SQL
    end

    def in_windows_sql
      @in_windows_sql ||= "[#{windows.map { |w| in_window_sql(w) }.join(", ")}]"
    end

    def in_window_sql(window)
      Clickhouse::ProductUsageBucket.sanitize_sql_array(
        ["toUInt8(bucket >= ? AND bucket < ?)", window.begin.utc, window.end.utc]
      )
    end

    # Rails' own matching (Events::BillingPeriodFilters::EventMatchingService) over the filters
    # the events matched: the segment's priced filters first, then the usual precedence. A
    # segment without a filter bills the rows matching none.
    def billed_by?(segment, matched_ids)
      @winners ||= {}
      winner = @winners.fetch([segment, matched_ids]) do
        source = filter_source(segment)
        @winners[[segment, matched_ids]] = filters_of(segment)
          .select { matched_ids.include?(it.id) }
          .min_by { source.filter_precedence(it) }
      end

      winner&.id == filter_id_of(segment)
    end

    def filter_source(segment)
      @filter_sources ||= {}
      @filter_sources[segment] ||= Events::BillingPeriodFilters::Sources::BillingSegment.new(billing_segment: segment)
    end

    def filters_of(segment)
      @filters ||= {}
      @filters[segment] ||= filter_source(segment).filters
    end

    def product_id_of(segment)
      segment.contract_rate_card.rate_card.product_id
    end

    def filter_id_of(segment)
      segment.contract_rate_card.rate_card.product_filter_id
    end

    def window(segment)
      Range.new(segment.started_at, BillingSegment.exclusive_end(segment.ended_at), true)
    end

    # Regrouped on the segment's current keys, as the events store groups (see FetchBucketsService).
    def expected_groups(segment, groups)
      keys = Array(segment.rate_properties["pricing_group_keys"])
      raise MissingGroupKeyError unless keys.all? { groups.key?(it) }

      keys.index_with { groups[it] }
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end
  end
end
