# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyBillableMetric'

      argument :id, String, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = BillableMetricsService.new(context[:current_user]).destroy(id)

        result.success? ? result.billable_metric : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
