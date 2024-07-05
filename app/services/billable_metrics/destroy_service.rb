# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
    def initialize(metric:)
      @metric = metric
      super
    end

    def call
      return result.not_found_failure!(resource: 'billable_metric') unless metric

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

      track_billable_metric_deleted

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

    def track_billable_metric_deleted
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'billable_metric_deleted',
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregation_type: metric.aggregation_type,
          aggregation_property: metric.field_name,
          organization_id: metric.organization_id
        }
      )
    end
  end
end
