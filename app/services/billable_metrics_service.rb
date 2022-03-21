# frozen_string_literal: true

class BillableMetricsService < BaseService
  def create(**args)
    return result.fail!('not_organization_member') unless organization_member?(args[:organization_id])

    metric = BillableMetric.new(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      billable_period: args[:billable_period]&.to_sym,
      aggregation_type: args[:aggregation_type]&.to_sym,
      pro_rata: args[:pro_rata],
      properties: args[:properties]
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
    metric.billable_period = args[:billable_period]&.to_sym
    metric.aggregation_type = args[:aggregation_type]&.to_sym
    metric.pro_rata = args[:pro_rata]
    metric.properties = args[:properties] if args[:properties]

    # TODO: better handling of validation errors
    metric.save!

    result.billable_metric = metric
    result
  end

  private

  def organization_member?(organization_id)
    return false unless result.user
    return false unless organization_id

    result.user.organizations.exists?(id: organization_id)
  end
end
