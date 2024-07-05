# frozen_string_literal: true

module BillableMetrics
  class CreateService < BaseService
    def create(args)
      organization = Organization.find_by(id: args[:organization_id])

      if args[:aggregation_type]&.to_sym == :custom_agg && !organization&.custom_aggregation
        return result.forbidden_failure!
      end

      ActiveRecord::Base.transaction do
        metric = BillableMetric.create!(
          organization_id: organization&.id,
          name: args[:name],
          code: args[:code],
          description: args[:description],
          recurring: args[:recurring] || false,
          aggregation_type: args[:aggregation_type]&.to_sym,
          field_name: args[:field_name],
          weighted_interval: args[:weighted_interval]&.to_sym
        )

        if args[:filters].present?
          BillableMetricFilters::CreateOrUpdateBatchService.call(
            billable_metric: metric,
            filters_params: args[:filters].map { |f| f.to_h.with_indifferent_access }
          ).raise_if_error!
        end

        result.billable_metric = metric
        track_billable_metric_created(metric)
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
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
