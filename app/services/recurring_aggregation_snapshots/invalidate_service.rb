# frozen_string_literal: true

module RecurringAggregationSnapshots
  class InvalidateService < BaseService
    Result = BaseResult

    def initialize(subscription:, codes: [])
      @subscription = subscription
      @codes = codes

      super
    end

    # Deletes the snapshots whose events were ingested again, so the next aggregation falls back to a
    # full scan instead of counting them twice as late events
    def call
      scope = RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: sharing_events_subscription_ids
      )
      scope = scope.where(billable_metric_id: billable_metric_ids) if codes.present?
      scope.delete_all

      result
    end

    private

    attr_reader :subscription, :codes

    # Recurring aggregations read every event of the external id, whichever subscription it was sent for
    def sharing_events_subscription_ids
      Subscription.where(organization_id: subscription.organization_id, external_id: subscription.external_id).select(:id)
    end

    def billable_metric_ids
      BillableMetric.with_discarded.where(organization_id: subscription.organization_id, code: codes).select(:id)
    end
  end
end
