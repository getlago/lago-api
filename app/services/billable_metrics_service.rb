# frozen_string_literal: true

class BillableMetricsService < BaseService
  def create(**args)
    metric = BillableMetric.create!(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      aggregation_type: args[:aggregation_type]&.to_sym
    )

    result.billable_metric = metric
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail!('unprocessable_entity', e.record.errors.full_messages.join('\n'))
  end

  def update(**args)
    metric = result.user.billable_metrics.find_by(id: args[:id])
    return result.fail!('not_found') unless metric

    metric.name = args[:name]
    metric.code = args[:code]
    metric.description = args[:description] if args[:description]
    metric.aggregation_type = args[:aggregation_type]&.to_sym
    metric.save!

    result.billable_metric = metric
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail!('unprocessable_entity', e.record.errors.full_messages.join('\n'))
  end

  def destroy(id)
    metric = result.user.billable_metrics.find_by(id: id)
    return result.fail!('not_found') unless metric

    metric.destroy!

    result.billable_metric = metric
    result
  end
end
