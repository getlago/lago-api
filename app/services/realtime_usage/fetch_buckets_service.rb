# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. `usage_buckets` is nil when the window cannot be answered, which leaves the
  # whole computation reading events.
  class FetchBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    BUCKET_SIZE = 15.minutes
    COVERAGE_CACHE_TTL = 5.minutes

    # What `connection_with_retry` re-raises once its retries are spent, plus the memory limit
    # it converts and never retries.
    READ_ERRORS = [
      *Events::Stores::Utils::ClickhouseConnection::RETRYABLE_ERRORS,
      Events::Stores::Clickhouse::MemoryLimitError
    ].freeze

    def initialize(subscription:, boundaries:, charges:)
      @subscription = subscription
      @boundaries = boundaries
      @charges = charges

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)
      return result if RealtimeUsage.deduplicated?(organization)
      return result if charges.empty?
      return result if window.nil?

      result.usage_buckets = fetch
      result
    end

    private

    attr_reader :subscription, :boundaries, :charges

    def organization
      @organization ||= subscription.organization
    end

    # An unreachable ClickHouse has to make current usage slow, not broken: no set at all
    # leaves every charge reading events.
    def fetch
      return nil unless covered?

      Events::Stores::UsageBucketSet.new(totals:, grouped_totals:, unservable_charge_ids:)
    rescue *READ_ERRORS => e
      Rails.logger.warn("Realtime usage bucket prefetch failed: #{e.class} #{e.message}")
      Sentry.capture_exception(e)
      nil
    end

    def totals
      rows.each_with_object({}) do |row, acc|
        # An unparsable row is dropped: its charge is unservable, so nothing reads its totals.
        next if row[:groups].nil?

        key = [row[:charge_id], row[:charge_filter_id]]
        acc[key] = sum_totals(acc[key], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].blank?

        charge_groups = (acc[[row[:charge_id], row[:charge_filter_id]]] ||= {})
        charge_groups[row[:groups]] = sum_totals(charge_groups[row[:groups]], row)
      end
    end

    def sum_totals(totals, row)
      Events::Stores::UsageBucketSet::Totals.new(
        units: (totals&.units || BigDecimal(0)) + row[:units],
        events_count: (totals&.events_count || 0) + row[:events_count]
      )
    end

    def rows
      @rows ||= read_rows.map do |charge_id, charge_filter_id, grouped_by, aggregation_type, units, events_count|
        {
          charge_id:,
          charge_filter_id:,
          aggregation_type:,
          groups: parse_groups(grouped_by),
          units: units.to_d,
          events_count: events_count.to_i
        }
      end
    end

    # The `organization_id, subscription_id, charge_id` scope is the table's sort order prefix,
    # so a request about one charge seeks instead of scanning the whole subscription. `FINAL`
    # collapses the versions of a bucket key, but its handling of the delete marker is version
    # and settings dependent, hence the explicit `is_deleted`.
    def read_rows
      Events::Stores::Utils::ClickhouseConnection.connection_with_retry do
        Clickhouse::UsageBucket
          .where(organization_id: organization.id, subscription_id: subscription.id, charge_id: charge_ids)
          .where(bucket: window, is_deleted: 0)
          .group(:charge_id, :charge_filter_id, :grouped_by, :aggregation_type)
          .pluck(Arel.sql("charge_id, charge_filter_id, grouped_by, aggregation_type, sum(units), sum(events_count)"))
      end
    end

    def charge_ids
      @charge_ids ||= charges.map(&:id)
    end

    # nil when the JSON is unreadable, which drift detection turns into a delegation rather
    # than an error.
    #
    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      parsed = JSON.parse(grouped_by.presence || "{}")

      parsed.transform_values(&:presence) if parsed.is_a?(Hash)
    rescue JSON::ParserError, TypeError
      nil
    end

    # Rails asks the store for one group per key of `Fees::ChargeService#grouped_by_keys`, so a
    # row grouped or aggregated another way answers another question than the fee asks. Only the
    # charge as a whole sees it, hence one drifting row delegating every filter of the charge.
    def unservable_charge_ids
      rows.each_with_object(Set.new) do |row, acc|
        acc << row[:charge_id] if drifted?(row)
      end
    end

    def drifted?(row)
      expected = expected_group_keys[[row[:charge_id], row[:charge_filter_id]]]
      return false if expected.nil?
      return true if row[:groups].nil?
      return true if row[:aggregation_type] != charges_by_id[row[:charge_id]].billable_metric.aggregation_type

      row[:groups].keys.sort != expected.sort
    end

    # The keys Rails would group each (charge, filter) by, `skip_grouping` aside: that one asks
    # for the ungrouped total, which stays the sum over the group rows. An uncovered row belongs
    # to a filter the charge no longer carries, which no fee reads.
    #
    # A charge mixing charge filters with charge-level `pricing_group_keys` legitimately drifts
    # and delegates: its synthetic default filter inherits those keys, where the pipeline writes
    # `grouped_by = {}` for an event matching no filter. Expected until the pipeline groups it.
    def expected_group_keys
      @expected_group_keys ||= charges.each_with_object({}) do |charge, acc|
        acc[[charge.id, ""]] = charge.pricing_group_keys || []
        charge.filters.each { acc[[charge.id, it.id]] = it.pricing_group_keys || [] }
      end
    end

    def charges_by_id
      @charges_by_id ||= charges.index_by(&:id)
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
    # nothing before `started_at` lands in that bucket. A truncated window (daily usage
    # backfill) ends mid-bucket and has the same problem at the other end.
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

    # Rows exist ⇒ trust them undercounts the first period of a freshly onboarded
    # organization, which is invisible: no error, only a lower number.
    def covered?
      coverage_start.present? && window.first >= coverage_start
    end

    def coverage_start
      return @coverage_start if defined?(@coverage_start)

      cached = Rails.cache.fetch("realtime-usage/coverage/#{organization.id}", expires_in: COVERAGE_CACHE_TTL) do
        earliest_bucket&.to_time&.iso8601(3)
      end

      @coverage_start = cached && Time.zone.parse(cached)
    end

    # ClickHouse returns the type default rather than NULL for an aggregate over no row, so an
    # organization with no bucket at all reads as the epoch.
    def earliest_bucket
      earliest = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do
        Clickhouse::UsageBucket.where(organization_id: organization.id).minimum(:bucket)
      end

      earliest if earliest.present? && earliest.to_i.positive?
    end
  end
end
