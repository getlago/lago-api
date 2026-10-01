# frozen_string_literal: true

module Resolvers
  module Customers
    class ProjectedUsageResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:view"

      description "Query the projected usage of the customer on the current billing period"

      argument :customer_id, type: ID, required: false
      argument :subscription_id, type: ID, required: true

      type Types::Customers::Usage::Projected, null: false

      def resolve(customer_id:, subscription_id:)
        result = Invoices::CustomerUsageService.with_ids(
          organization_id: current_organization.id,
          customer_id:,
          subscription_id:,
          apply_taxes: false,
          with_projection: true,
          use_usage_buckets: true
        ).call

        return result_error(result) unless result.success?

        context.scoped_set!(:usage_projections, result.usage.projections)
        result.usage
      end
    end
  end
end
