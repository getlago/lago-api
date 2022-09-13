# frozen_string_literal: true

module BillableMetrics
  class UpdateService < BaseService
    def update(**args)
      metric = result.user.billable_metrics.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'billable_metric') unless metric

      metric.name = args[:name]
      metric.description = args[:description] if args[:description]

      # NOTE: Only name and description are editable if billable metric
      #       is attached to subscriptions
      unless metric.attached_to_subscriptions?
        metric.code = args[:code]
        metric.aggregation_type = args[:aggregation_type]&.to_sym
        metric.field_name = args[:field_name]
      end

      metric.save!

      result.billable_metric = metric
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, code:, params:)
      metric = organization.billable_metrics.find_by(code: code)
      return result.not_found_failure!(resource: 'billable_metric') unless metric

      metric.name = params[:name] if params.key?(:name)
      metric.description = params[:description] if params.key?(:description)

      unless metric.attached_to_subscriptions?
        metric.code = params[:code] if params.key?(:code)
        metric.aggregation_type = params[:aggregation_type] if params.key?(:aggregation_type)
        metric.field_name = params[:field_name] if params.key?(:field_name)
      end

      metric.save!

      result.billable_metric = metric
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
