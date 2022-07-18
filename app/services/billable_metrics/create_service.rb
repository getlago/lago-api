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

      Analytics.track(
        event: 'billable_metric_created',
        user_id: result.user.memberships.first.id, # TODO: Hash the value
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregationType: metric.aggregation_type,
          aggregationProperty: metric.field_name,
          hostingType: ENV['LAGO_CLOUD'] ? "cloud" : "self",
          organizationId: metric.organization_id, # TODO: hash
          version: "" # TODO
        },
      )


      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
