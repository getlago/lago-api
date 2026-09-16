# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
    Result = BaseResult[:billable_metric]

    def initialize(metric:)
      @metric = metric
      super
    end

    activity_loggable(
      action: "billable_metric.deleted",
      record: -> { metric }
    )

    def call
      return result.not_found_failure!(resource: "billable_metric") unless metric

      # Deleting the metric would discard its filters and orphan any kept
      # product filter value that references them, so block instead of cascade.
      if metric.product_filter_values.exists?
        return result.single_validation_failure!(field: :billable_metric, error_code: "referenced_by_product_filter")
      end

      BillableMetrics::ExpressionCacheService.expire_cache(metric.organization.id, metric.code)

      draft_invoice_ids = Invoice.draft.joins(plans: [:billable_metrics])
        .where(billable_metrics: {id: metric.id}).distinct.pluck(:id)

      ActiveRecord::Base.transaction do
        metric.discard!

        # rubocop:disable Rails/SkipsModelValidations
        metric.alerts.update_all(deleted_at: Time.current)
        metric.charges.update_all(deleted_at: Time.current)
        Invoice.where(id: draft_invoice_ids).update_all(ready_to_be_refreshed: true)
        # rubocop:enable Rails/SkipsModelValidations
      end

      BillableMetricFilters::DestroyAllJob.perform_later(metric.id)

      SendWebhookJob.perform_after_commit("billable_metric.deleted", metric)

      result.billable_metric = metric
      result
    end

    private

    attr_reader :metric
  end
end
