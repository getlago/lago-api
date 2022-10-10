# frozen_string_literal: true

module BillableMetrics
  class CreateService < BaseService
    def create(**args)
      ActiveRecord::Base.transaction do
        metric = BillableMetric.create!(
          organization_id: args[:organization_id],
          name: args[:name],
          code: args[:code],
          description: args[:description],
          aggregation_type: args[:aggregation_type]&.to_sym,
          field_name: args[:field_name],
        )

        if args[:group].present?
          Groups::CreateBatchService.call(
            billable_metric: metric,
            group_params: args[:group].with_indifferent_access,
          )
        end

        result.billable_metric = metric
        track_billable_metric_created(metric)
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def track_billable_metric_created(metric)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'billable_metric_created',
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregation_type: metric.aggregation_type,
          aggregation_property: metric.field_name,
          organization_id: metric.organization_id,
        },
      )
    end
  end
end
