# frozen_string_literal: true

module BillableMetrics
  class UpdateService < BaseService
    def update(**args)
      metric = result.user.billable_metrics.find_by(id: args[:id])
      return result.fail!('not_found') unless metric

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
      result.fail_with_validations!(e.record)
    end
  end
end
