# frozen_string_literal: true

class BillableMetricsService < BaseService
  def create(**args)
    metric = BillableMetric.create!(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      aggregation_type: args[:aggregation_type]&.to_sym,
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
    metric.description = args[:description] if args[:description]

    # NOTE: Only name and description are editable if billable metric
    #       is attached to subscriptions
    unless metric.attached_to_subscriptions?
      metric.code = args[:code]
      metric.aggregation_type = args[:aggregation_type]&.to_sym
    end

    metric.save!

    result.billable_metric = metric
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail!('unprocessable_entity', e.record.errors.full_messages.join('\n'))
  end

  def destroy(id)
    metric = result.user.billable_metrics.find_by(id: id)
    return result.fail!('not_found') unless metric

    unless metric.deletable?
      return result.fail!(
        'forbidden',
        'Billable metric is attached to an active subscriptions',
      )
    end

    metric.destroy!

    result.billable_metric = metric
    result
  end
end
