# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. `usage_buckets` is nil when ClickHouse is unreachable, which leaves the whole
  # computation reading events.
  class FetchBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    BUCKET_SIZE = 15.minutes

    def initialize(subscription:, boundaries:)
      @subscription = subscription
      @boundaries = boundaries

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)
      return result if RealtimeUsage.deduplicated?(organization)

      result.usage_buckets = Events::Stores::UsageBucketSet.new(totals:, grouped_totals:)
      result
    rescue ActiveRecord::ActiveRecordError => e
      # An unreachable ClickHouse has to make current usage slow, not broken.
      Rails.logger.warn("Realtime usage bucket prefetch failed: #{e.class} #{e.message}")
      Sentry.capture_exception(e)
      result
    end

    private

    attr_reader :subscription, :boundaries

    def organization
      @organization ||= subscription.organization
    end

    def totals
      rows.each_with_object({}) do |row, acc|
        key = [row[:charge_id], row[:charge_filter_id]]
        acc[key] = sum_totals(acc[key], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[[row[:charge_id], row[:charge_filter_id]]] ||= {})
        groups[row[:groups]] = sum_totals(groups[row[:groups]], row)
      end
    end

    def sum_totals(totals, row)
      Events::Stores::UsageBucketSet::Totals.new(
        units: (totals&.units || BigDecimal(0)) + row[:units],
        events_count: (totals&.events_count || 0) + row[:events_count]
      )
    end

    def rows
      @rows ||= Clickhouse::UsageBucket
        .where(organization_id: organization.id, subscription_id: subscription.id)
        .where(bucket: window)
        .group(:charge_id, :charge_filter_id, :grouped_by)
        .pluck(Arel.sql("charge_id, charge_filter_id, grouped_by, sum(units), sum(events_count)"))
        .map do |charge_id, charge_filter_id, grouped_by, units, events_count|
          {charge_id:, charge_filter_id:, groups: parse_groups(grouped_by), units: units.to_d, events_count: events_count.to_i}
        end
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end

    # Widening the window to whole buckets cannot pull in usage from a neighbouring period:
    # the pipeline attributes an event to a subscription only within its lifetime, so an
    # upgrade or a termination mid-bucket routes each event to the right subscription however
    # the boundary falls.
    def window
      @window ||= floor_to_bucket(boundaries.charges_from_datetime)...ceil_to_bucket(boundaries.charges_to_datetime)
    end

    def floor_to_bucket(time)
      Time.zone.at(time.to_i - (time.to_i % BUCKET_SIZE.to_i))
    end

    def ceil_to_bucket(time)
      floor = floor_to_bucket(time)

      (floor == time) ? floor : floor + BUCKET_SIZE
    end
  end
end
