# frozen_string_literal: true

class BillableMetricsService < BaseService
  def create(**args)
    if !organization_member?(args[:organization_id])
      result.fail!('not_organization_member')
      return result
    end

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
