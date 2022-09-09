# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
    def destroy(id)
      metric = result.user.billable_metrics.find_by(id: id)
      return result.not_found_failure!(resource: 'billable_metric') unless metric
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless metric.deletable?

      metric.destroy!

      result.billable_metric = metric
      result
    end

    def destroy_from_api(organization:, code:)
      metric = organization.billable_metrics.find_by(code: code)
      return result.not_found_failure!(resource: 'billable_metric') unless metric
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless metric.deletable?

      metric.destroy!

      result.billable_metric = metric
      result
    end
  end
end
