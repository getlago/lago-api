# frozen_string_literal: true

module BillableMetricFilters
  class RefreshDraftInvoicesJob < ApplicationJob
    queue_as :default

    def perform(billable_metric_id)
      billable_metric = BillableMetric.find_by(id: billable_metric_id)
      return unless billable_metric
      plan_ids = billable_metric.plans.distinct.ids
      return if plan_ids.empty?

      Invoice.draft
        .where(id: InvoiceSubscription
                     .where(subscription_id: Subscription.where(plan_id: plan_ids).select(:id))
                     .select(:invoice_id).in_batches do |batch|
          batch.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
        end
    end
  end
end
