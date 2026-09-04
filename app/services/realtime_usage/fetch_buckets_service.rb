# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. `usage_buckets` is nil when the window cannot be answered, which leaves the
  # whole computation reading events.
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
      return result if window.nil?

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

    def window
      return @window if defined?(@window)

      @window = servable_window? ? (floor_to_bucket(from)...to) : nil
    end

    def from
      boundaries.charges_from_datetime
    end

    def to
      boundaries.charges_to_datetime
    end

    # A window opening inside a bucket would count the whole bucket, except on the very first
    # period: the pipeline attributes an event to a subscription only within its lifetime, so
    # nothing before `started_at` lands in that bucket.
    #
    # `max_timestamp` marks the daily usage backfill, which is kept off this path today.
    def servable_window?
      return false if from.blank? || to.blank?
      return false if boundaries.max_timestamp.present?

      aligned?(from) || from == subscription.started_at
    end

    def aligned?(time)
      (time.to_i % BUCKET_SIZE.to_i).zero? && time.usec.zero?
    end

    def floor_to_bucket(time)
      Time.zone.at(time.to_i - (time.to_i % BUCKET_SIZE.to_i))
    end
  end
end
