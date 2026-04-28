# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module Plans
        class Update < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"

          graphql_name "UpdateQuotePlan"
          description "Updates a plan billing item on a quote version"

          argument :quote_version_id, ID, required: true
          argument :id, ID, required: true
          argument :plan_id, ID, required: false
          argument :external_subscription_id, String, required: false

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::Plans::UpdateService.call(
              quote_version:,
              id: args[:id],
              params: args.except(:quote_version_id, :id)
            )
            result.success? ? result.quote_version : result_error(result)
          end
        end
      end
    end
  end
end
