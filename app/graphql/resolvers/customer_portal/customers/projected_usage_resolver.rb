# frozen_string_literal: true

module Resolvers
  module CustomerPortal
    module Customers
      class ProjectedUsageResolver < Resolvers::BaseResolver
        include AuthenticableCustomerPortalUser

        description "Query the projected usage of the customer on the current billing period"

        argument :subscription_id, type: ID, required: true

        type Types::Customers::Usage::Projected, null: false

        def resolve(subscription_id:)
          result = Invoices::CustomerUsageService.with_ids(
            organization_id: context[:customer_portal_user].organization_id,
            customer_id: context[:customer_portal_user].id,
            subscription_id:,
            apply_taxes: false,
            with_projection: true,
            use_usage_buckets: true
          ).call

          return result_error(result) unless result.success?

          context.scoped_set!(:usage_projections, result.usage.projections)
          result.usage
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "customer")
        end
      end
    end
  end
end
