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
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
