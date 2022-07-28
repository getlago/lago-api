# frozen_string_literal: true

module BillableMetrics
  class CreateService < BaseService
    def create(**args)
      metric = BillableMetric.create!(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        description: args[:description],
        aggregation_type: args[:aggregation_type]&.to_sym,
        field_name: args[:field_name],
      )

      result.billable_metric = metric
      track_billable_metric_created(metric)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
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
          organization_id: metric.organization_id
        }
      )
    end
  end
end
