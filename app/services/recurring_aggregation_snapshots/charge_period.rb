# frozen_string_literal: true

module RecurringAggregationSnapshots
  # The latest period of a charge closed before from_datetime. Loads the marker, the filter check
  # and the snapshots once, for all charge filters.
  class ChargePeriod
    def initialize(subscription:, charge:, from_datetime:)
      @subscription = subscription
      @charge = charge
      @from_datetime = from_datetime
    end

    # Marker and snapshots of the charge filter's bucket, or nil without a marker. A marker the
    # filters changed since gives [], a full scan rather than the previous subscription.
    def period(charge_filter:)
      return unless marker
      return [] if filters_changed?

      [marker, records.fetch(charge_filter&.id, [])]
    end

    private

    attr_reader :subscription, :charge, :from_datetime

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
        charge_snapshots
          .where(charge_filter_id: [nil, *charge.filters.ids])
          .of_period(latest_to_datetime)
          .group_by(&:charge_filter_id)
      end
    end

    def filters_changed?
      return @filters_changed if defined?(@filters_changed)

      @filters_changed = RecurringAggregationSnapshot.filters_changed_since?(
        organization_id: subscription.organization_id, charge_ids: charge.id, watermark: marker.watermark
      )
    end
  end
end
