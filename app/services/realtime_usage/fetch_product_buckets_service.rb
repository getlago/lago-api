# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of a contract's billing segments from the ClickHouse product
  # buckets, in one query. Like FetchBucketsService, a failed read is a service failure that
  # leaves the caller reading events, and the read never raises.
  #
  # The set is keyed by [contract rate card id, product filter id] in place of [charge id, charge
  # filter id]: in a computation, a card prices one segment, which reads one product filter.
  class FetchProductBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    # The segments the buckets can answer exactly, which the provider serves and this reads:
    #   * a window on bucket walls, as a bucket is summed whole. Segments start on customer-local
    #     midnights and arrears rates on UTC ones, so this only rules out the unexpected.
    #   * one segment per product and product filter, the key of the buckets: two segments of one
    #     pair could not tell their rows apart.
    def self.readable_segments(billing_segments)
      billing_segments
        .select { |segment| on_bucket_walls?(segment) }
        .group_by { |segment| slice_of(segment) }
        .filter_map { |_, segments| segments.sole if segments.one? }
    end

    def self.on_bucket_walls?(segment)
      [segment.started_at, BillingSegment.exclusive_end(segment.ended_at)].all? do |time|
        RealtimeUsage.floor_to_bucket(time) == time
      end
    end

    def self.slice_of(segment)
      rate_card = segment.contract_rate_card.rate_card

      [rate_card.product_id, rate_card.product_filter_id || ""]
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

    def segments_by_slice
      @segments_by_slice ||= read_segments.index_by { |segment| self.class.slice_of(segment) }
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

    def rows
      @rows ||= Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }
    end

    def fetch_rows
      read_segments.map { |segment| segment_scope(segment) }.reduce(:or)
        .where(organization_id: organization.id, contract_id: contract.id, is_deleted: 0)
        .group(:product_id, :product_filter_id, :grouped_by, :aggregation_type)
        .pluck(Arel.sql(<<~SQL.squish))
          product_id, product_filter_id, grouped_by, aggregation_type,
          sum(units), max(units), argMax(units, last_event_at), max(last_event_at), sum(events_count),
          sum(precise_total_amount_cents)
        SQL
        .map do |product_id, product_filter_id, grouped_by, aggregation_type, sum_units, max_units, latest_units, last_event_at, events_count, precise_total_amount_cents|
          segment = segments_by_slice.fetch([product_id, product_filter_id])
          units = {sum_units:, max_units:, latest_units:}
            .fetch(FetchBucketsService::UNITS_BY_AGGREGATION_TYPE.fetch(aggregation_type, :sum_units))

          {
            key: [segment.contract_rate_card_id, product_filter_id],
            groups: expected_groups(segment, parse_groups(grouped_by)),
            aggregation_type:,
            units: units.to_d,
            last_event_at: last_event_at.to_time,
            events_count: events_count.to_i,
            precise_total_amount_cents: precise_total_amount_cents.to_d
          }
        end
    end

    # A card version takes over at a customer-local midnight, which the pipeline does not know:
    # in the day around a version change it counts an event once per version that may apply,
    # tagged with that version's effective date, and an empty tag everywhere else. The segment's
    # window starts and ends on those midnights, which are bucket walls as every timezone offset
    # is a multiple of 15 minutes, so it keeps the rows of its own version and drops the others.
    def segment_scope(segment)
      product_id, product_filter_id = self.class.slice_of(segment)

      Clickhouse::ProductUsageBucket.where(
        product_id:,
        product_filter_id:,
        card_effective_date: ["", segment.contract_rate_card.effective_date.iso8601],
        bucket: window(segment)
      )
    end

    def window(segment)
      Range.new(segment.started_at, BillingSegment.exclusive_end(segment.ended_at), true)
    end

    # Regrouped on the segment's current keys, as the events store groups (see FetchBucketsService).
    def expected_groups(segment, groups)
      Array(segment.rate_properties["pricing_group_keys"]).index_with { groups[it] }
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end
  end
end
