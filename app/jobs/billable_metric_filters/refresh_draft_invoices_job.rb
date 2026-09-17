# frozen_string_literal: true

module BillableMetricFilters
  class RefreshDraftInvoicesJob < ApplicationJob
    queue_as :default

    def perform(billable_metric_id)
      billable_metric = BillableMetric.find_by(id: billable_metric_id)
      return unless billable_metric

      # The organization_id is redundant with the plans join but added as an optimisation:
      # it avoids a full scan of the invoices table by using the idx_invoices_organization_id_status index.
      Invoice.draft
        .where(organization_id: billable_metric.organization_id)
        .joins(plans: [:billable_metrics])
        .where(billable_metrics: {id: billable_metric.id})
        .distinct
        .in_batches do |batch|
          batch.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
        end
    end
  end
end
