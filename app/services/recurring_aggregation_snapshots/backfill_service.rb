# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Writes the snapshots of the latest invoiced period, aggregated as its invoice did, so reads need
  # not wait for a period to close with writes on. A read only starts from the latest period.
  class BackfillService < BaseService
    Result = BaseResult[:invoice_subscription, :written_charges, :skipped_charges, :failed_charges]

    # One charge failing on the events store leaves the others to run: a rerun only redoes the failed ones
    CHARGE_ERRORS = [
      ActiveRecord::ActiveRecordError,
      BaseService::FailedResult,
      Events::Stores::Clickhouse::MemoryLimitError
    ].freeze

    def initialize(subscription:)
      @subscription = subscription

      super
    end

    def call
      return result.not_allowed_failure!(code: "subscription_not_active") unless subscription.active?

      result.written_charges = []
      result.skipped_charges = []
      result.failed_charges = []
      result.invoice_subscription = invoice_subscription
      return result unless invoice_subscription

      started_at = Time.current

      charges.find_each do |charge|
        metered_item = Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries:)
        next unless RecurringAggregationSnapshot.eligible?(metered_item:, billing_context:)

        backfill_charge(charge, metered_item, started_at)
      end

      result
    end

    private

    attr_reader :subscription

    def backfill_charge(charge, metered_item, started_at)
      charge_result = Fees::ChargeService.call(
        invoice: nil,
        metered_item:,
        billing_context:,
        options: Fees::ChargeService::Options.new(context: :snapshot_backfill, skip_adjusted_fees: true)
      )

      if charge_result.failure?
        result.failed_charges << charge
      elsif marker_written?(charge, since: started_at)
        result.written_charges << charge
      else
        result.skipped_charges << charge
      end
    rescue *CHARGE_ERRORS
      result.failed_charges << charge
    end

    # Advance charges and pay in advance invoices can share the boundary of the period.
    # An active subscription has no terminating invoice.
    def invoice_subscription
      return @invoice_subscription if defined?(@invoice_subscription)

      @invoice_subscription = subscription.invoice_subscriptions
        .subscription_periodic
        .where.not(timestamp: nil)
        .where("charges_from_datetime < charges_to_datetime")
        .order(charges_to_datetime: :desc, created_at: :desc)
        .first
    end

    # The boundaries Invoices::CalculateFeesService gave the charges of that invoice
    def boundaries
      @boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: invoice_subscription.from_datetime,
        to_datetime: invoice_subscription.to_datetime,
        charges_from_datetime: invoice_subscription.charges_from_datetime,
        charges_to_datetime: invoice_subscription.charges_to_datetime,
        fixed_charges_from_datetime: invoice_subscription.fixed_charges_from_datetime,
        fixed_charges_to_datetime: invoice_subscription.fixed_charges_to_datetime,
        timestamp: invoice_subscription.timestamp,
        charges_duration: Subscriptions::DatesService.new_instance(subscription, invoice_subscription.timestamp).charges_duration_in_days
      )
    end

    def billing_context
      @billing_context ||= Billing::Context.from(subscription:)
    end

    def charges
      subscription.plan.charges
        .includes(:applied_pricing_unit, billable_metric: :organization, filters: {values: :billable_metric_filter})
        .joins(:billable_metric)
        .where(billable_metrics: {recurring: true})
    end

    # A bucket without recurring units leaves the charge without snapshots (see Fees::ChargeService)
    def marker_written?(charge, since:)
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        charge_id: charge.id,
        charge_filter_id: nil,
        to_datetime: boundaries.charges_to_datetime,
        watermark: (since - RecurringAggregationSnapshot::WATERMARK_LAG).floor(3)..
      ).exists?
    end
  end
end
