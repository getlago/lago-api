# frozen_string_literal: true

class BillableMetricsService < BaseService
  def create(**args)
    metric = BillableMetric.new(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      aggregation_type: args[:aggregation_type]&.to_sym
    )

    # TODO: better handling of validation errors
    metric.save!

    result.billable_metric = metric
    result
  end

  def update(**args)
    metric = result.user.billable_metrics.find_by(id: args[:id])
    return result.fail!('not_found') unless metric

    metric.name = args[:name]
    metric.code = args[:code]
    metric.description = args[:description] if args[:description]
    metric.aggregation_type = args[:aggregation_type]&.to_sym

    # TODO: better handling of validation errors
    metric.save!

    result.billable_metric = metric
    result
  end

  def destroy(id)
    metric = result.user.billable_metrics.find_by(id: id)
    return result.fail!('not_found') unless metric

    metric.destroy!

    result.billable_metric = metric
    result
  end
end
