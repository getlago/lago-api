# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of every product of one contract over one window from the product usage buckets,
  # the product catalog's counterpart of FetchBucketsService. A failed read is a service failure,
  # which leaves the caller reading events.
  #
  # The set is keyed by `[product_id, product_filter_id]`, in the slots UsageBucketSet names
  # `charge_id` and `charge_filter_id`. Groups are returned as written, and `group_keys` lists,
  # per key, every set of group keys the rows carry: the reader serves a billing segment only
  # when they are the keys it prices with, which a rate override or a key change can make differ.
  class FetchProductBucketsService < BaseService
    Result = BaseResult[:usage_buckets, :group_keys]

    def initialize(contract:, from_datetime:, to_datetime:)
      @contract = contract
      @from_datetime = from_datetime
      @to_datetime = to_datetime

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)

      result.usage_buckets = Events::Stores::UsageBucketSet.new(totals:, grouped_totals:)
      result.group_keys = group_keys
      result
    rescue *READ_ERRORS => e
      Sentry.capture_exception(e)
      result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
    end

    private

    attr_reader :contract, :from_datetime, :to_datetime

    def organization
      @organization ||= contract.organization
    end

    def totals
      rows.each_with_object({}) do |row, acc|
        key = [row[:product_id], row[:product_filter_id]]
        acc[key] = combine_totals(acc[key], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[[row[:product_id], row[:product_filter_id]]] ||= {})
        groups[row[:groups]] = combine_totals(groups[row[:groups]], row)
      end
    end

    def group_keys
      rows.each_with_object({}) do |row, acc|
        (acc[[row[:product_id], row[:product_filter_id]]] ||= Set.new) << row[:groups].keys.sort
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
      Clickhouse::ProductUsageBucket
        .where(organization_id: organization.id, contract_id: contract.id)
        .where(bucket: from_datetime...to_datetime, is_deleted: 0)
        .group(:product_id, :product_filter_id, :grouped_by, :aggregation_type)
        .pluck(Arel.sql(<<~SQL.squish))
          product_id, product_filter_id, grouped_by, aggregation_type,
          sum(units), max(units), argMax(units, last_event_at), max(last_event_at), sum(events_count),
          sum(precise_total_amount_cents)
        SQL
        .map do |product_id, product_filter_id, grouped_by, aggregation_type, sum_units, max_units, latest_units, last_event_at, events_count, precise_total_amount_cents|
          units = {sum_units:, max_units:, latest_units:}
            .fetch(FetchBucketsService::UNITS_BY_AGGREGATION_TYPE.fetch(aggregation_type, :sum_units))

          {
            product_id:,
            product_filter_id:,
            groups: parse_groups(grouped_by),
            aggregation_type:,
            units: units.to_d,
            last_event_at: last_event_at.to_time,
            events_count: events_count.to_i,
            precise_total_amount_cents: precise_total_amount_cents.to_d
          }
        end
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end
  end
end
