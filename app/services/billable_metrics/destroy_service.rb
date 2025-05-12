# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
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

      BillableMetrics::ExpressionCacheService.expire_cache(metric.organization.id, metric.code)

      draft_invoice_ids = Invoice.draft.joins(plans: [:billable_metrics])
        .where(billable_metrics: {id: metric.id}).distinct.pluck(:id)

      ActiveRecord::Base.transaction do
        metric.discard!
        metric.charges.discard_all

        discard_filters

        Invoice.where(id: draft_invoice_ids).update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
      end

      # NOTE: Discard all related events asynchronously.
      BillableMetrics::DeleteEventsJob.perform_later(metric)

      result.billable_metric = metric
      result
    end

    private

    attr_reader :metric

    def discard_filters
      metric.filters.each do |filter|
        filter.filter_values.discard_all
        filter.charge_filters.discard_all
        filter.discard!
      end
    end
  end
end
