# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyBillableMetric'
      description 'Deletes a Billable metric'

      argument :id, String, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ::BillableMetrics::DestroyService
          .new
          .destroy(
            metric: context[:current_user].billable_metrics.find_by(id:),
          )

        result.success? ? result.billable_metric : result_error(result)
      end
    end
  end
end
