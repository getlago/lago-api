# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Checks the snapshots of the latest closed period of each recurring charge of a subscription.
  # The fee computation of that period runs again at the watermark each bucket was written with,
  # nothing persisted, and its snapshot values are compared with the stored rows per
  # (charge, charge filter, group). Needs no read path: it only checks what the invoices wrote.
  class AuditService < BaseService
    Result = BaseResult[
      :rows,
      :differences,
      :audited_charges_count,
      :snapshot_charges_count,
      :charges_without_marker,
      :charges_without_invoice
    ]

    Values = Data.define(:units, :events_count)

    Row = Data.define(
      :charge_id,
      :billable_metric_code,
      :charge_filter_id,
      :grouped_by,
      :to_datetime,
      :watermark,
      :bounded,
      :stored,
      :recomputed
    ) do
      def different?
        stored != recomputed
      end
    end

    def initialize(subscription:)
      @subscription = subscription

      super
    end

    def call
      result.rows = []
      result.charges_without_marker = []
      result.charges_without_invoice = []
      result.audited_charges_count = audited_charges.size
      result.snapshot_charges_count = 0

      audited_charges.each { audit_charge(it) }

      result.differences = result.rows.select(&:different?)
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :subscription

    def audit_charge(charge)
      snapshots = latest_period_snapshots(charge)
      return if snapshots.empty?

      result.snapshot_charges_count += 1
      result.charges_without_marker << charge.id if snapshots.none? { it.charge_filter_id.nil? }

      invoice_subscription = period_invoice_subscription(snapshots.first.to_datetime)
      unless invoice_subscription
        result.charges_without_invoice << charge.id
        return
      end

      stored_buckets = snapshots.map(&:charge_filter_id).uniq
      latest_watermark = snapshots.map(&:watermark).max

      # Buckets keep the watermark of the run that wrote them last, so a charge may hold several.
      # A bucket stored under none is compared at the latest one.
      snapshots.group_by(&:watermark).each do |watermark, watermark_snapshots|
        buckets = watermark_snapshots.map(&:charge_filter_id).uniq
        recomputed = recompute(charge, invoice_subscription, watermark).select do |(charge_filter_id, _), _|
          buckets.include?(charge_filter_id) || (watermark == latest_watermark && stored_buckets.exclude?(charge_filter_id))
        end

        stored = watermark_snapshots.to_h do
          [[it.charge_filter_id, normalized(it.grouped_by)], Values.new(units: it.units, events_count: it.events_count)]
        end

        (stored.keys | recomputed.keys).each do |key|
          charge_filter_id, grouped_by = key

          result.rows << Row.new(
            charge_id: charge.id,
            billable_metric_code: charge.billable_metric.code,
            charge_filter_id:,
            grouped_by:,
            to_datetime: watermark_snapshots.first.to_datetime,
            watermark:,
            bounded: !charge.billable_metric.weighted_sum_agg?,
            stored: stored[key],
            recomputed: recomputed[key]
          )
        end
      end
    end

    def latest_period_snapshots(charge)
      scope = RecurringAggregationSnapshot.where(organization_id: subscription.organization_id, subscription_id: subscription.id, charge_id: charge.id)
      scope.where(to_datetime: scope.select("MAX(to_datetime)")).to_a
    end

    def period_invoice_subscription(to_datetime)
      subscription.invoice_subscriptions.where(charges_to_datetime: to_datetime).order(created_at: :desc).first
    end

    # Weighted sum writes its recurring CachedAggregation rows even in a preview: rolled back.
    def recompute(charge, invoice_subscription, watermark)
      recurring_snapshots = nil

      ApplicationRecord.transaction(requires_new: true) do
        recurring_snapshots = Fees::ChargeService.call!(
          invoice: nil,
          metered_item: Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries: boundaries(invoice_subscription)),
          billing_context: Billing::Context.from(subscription:),
          options: Fees::ChargeService::Options.new(context: :invoice_preview, snapshot_watermark: watermark)
        ).recurring_snapshots

        raise ActiveRecord::Rollback
      end

      recurring_snapshots.each_with_object({}) do |snapshot, values|
        snapshot[:values].each do |value|
          key = [snapshot[:charge_filter]&.id, normalized(value[:grouped_by])]
          values[key] = Values.new(units: value[:units], events_count: value[:events_count])
        end
      end
    end

    def boundaries(invoice_subscription)
      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        invoice_subscription.timestamp,
        current_usage: subscription.terminated? && subscription.upgraded?
      )

      BillingPeriodBoundaries.new(
        from_datetime: invoice_subscription.from_datetime,
        to_datetime: invoice_subscription.to_datetime,
        charges_from_datetime: invoice_subscription.charges_from_datetime,
        charges_to_datetime: invoice_subscription.charges_to_datetime,
        timestamp: invoice_subscription.timestamp,
        charges_duration: date_service.charges_duration_in_days
      )
    end

    # Stored group values come back from JSON, the recomputed ones from the events
    def normalized(grouped_by)
      (grouped_by || {}).transform_values { it&.to_s }
    end

    def audited_charges
      @audited_charges ||= subscription.plan.charges.includes(:billable_metric, :filters).select do |charge|
        charge.billable_metric.recurring? &&
          Fees::ChargeService::SNAPSHOT_AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type)
      end
    end
  end
end
