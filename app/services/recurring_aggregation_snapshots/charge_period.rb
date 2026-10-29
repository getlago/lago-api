# frozen_string_literal: true

module RecurringAggregationSnapshots
  # The latest period of a charge closed before from_datetime. Loads the marker, the filter check
  # and the snapshots once, for all charge filters.
  class ChargePeriod
    # charge_filter_ids: the buckets to load besides the default one, every filter of the charge when nil
    # grouped_by_values: loads only the snapshots of that group, plus one per bucket for the marker
    # and the grouping keys check. A key left out matches every value.
    def initialize(subscription:, charge:, from_datetime:, charge_filter_ids: nil, grouped_by_values: nil)
      @subscription = subscription
      @charge = charge
      @from_datetime = from_datetime
      @charge_filter_ids = charge_filter_ids
      @grouped_by_values = grouped_by_values.presence
    end

    # Marker and snapshots of the charge filter's bucket, or nil without a marker. A marker the
    # filters changed since gives [], a full scan rather than the previous subscription.
    def period(charge_filter:)
      return unless marker
      return [] if filters_changed?

      [marker, records.fetch(charge_filter&.id, [])]
    end

    private

    attr_reader :subscription, :charge, :from_datetime, :charge_filter_ids, :grouped_by_values

    def charge_snapshots
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        charge_id: charge.id
      )
    end

    # The default bucket keeps a row for every closed period, other buckets only for groups with
    # units or events: the marker tells a bucket without usage from a period never closed.
    def marker
      records[nil]&.first
    end

    # One statement reads the marker and the buckets, so a run rewriting the period cannot land in between
    def records
      @records ||= begin
        latest_to_datetime = charge_snapshots
          .where(charge_filter_id: nil, to_datetime: ...from_datetime)
          .order(to_datetime: :desc)
          .limit(1)
          .select(:to_datetime)

        # Listing the buckets lets the period index serve to_datetime too
        period_snapshots = charge_snapshots
          .where(charge_filter_id: [nil, *(charge_filter_ids || charge.filters.ids)])
          .of_period(latest_to_datetime)
        period_snapshots = group_snapshots(period_snapshots) if grouped_by_values
        period_snapshots.group_by(&:charge_filter_id)
      end
    end

    # A blank value matches a missing one, as the stores group them together
    def group_snapshots(period_snapshots)
      bucket_snapshots = period_snapshots.select("DISTINCT ON (charge_filter_id) id").order(:charge_filter_id, :id)
      conditions = grouped_by_values.map do |key, value|
        if value.to_s.strip.empty?
          ActiveRecord::Base.sanitize_sql_for_conditions(["COALESCE(TRIM(grouped_by ->> ?), '') = ''", key.to_s])
        else
          ActiveRecord::Base.sanitize_sql_for_conditions(["grouped_by ->> ? = ?", key.to_s, value.to_s])
        end
      end

      period_snapshots.where(id: bucket_snapshots).or(period_snapshots.where(conditions.join(" AND ")))
    end

    def filters_changed?
      return @filters_changed if defined?(@filters_changed)

      @filters_changed = RecurringAggregationSnapshot.filters_changed_since?(
        organization_id: subscription.organization_id, charge_ids: charge.id, watermark: marker.watermark
      )
    end
  end
end
