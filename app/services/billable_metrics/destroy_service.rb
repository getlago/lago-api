# frozen_string_literal: true

module BillableMetrics
  class DestroyService < BaseService
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

    def destroy_from_api(organization:, code:)
      metric = organization.billable_metrics.find_by(code: code)
      return result.fail!('not_found', 'billable metric does not exist') unless metric

      unless metric.deletable?
        return result.fail!(
          'forbidden',
          'billable metric is attached to an active subscriptions',
          )
      end

      metric.destroy!

      result.billable_metric = metric
      result
    end
  end
end
