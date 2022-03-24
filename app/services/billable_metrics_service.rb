# frozen_string_literal: true

class BillableMetricsService < BaseService
  include ScopedToOrganization

  def create(**args)
    return result.fail!('not_organization_member') unless organization_member?(args[:organization_id])

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
    metric = BillableMetric.find_by(id: args[:id])
    return result.fail!('not_found') unless metric
    return result.fail!('not_organization_member') unless organization_member?(metric.organization_id)

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
    metric = BillableMetric.find_by(id: id)
    return result.fail!('not_found') unless metric
    return result.fail!('not_organization_member') unless organization_member?(metric.organization_id)

    metric.destroy!

    result.billable_metric = metric
    result
  end
end
