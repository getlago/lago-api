# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module Plans
        class Add < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"

          graphql_name "AddQuotePlan"
          description "Adds a plan billing item to a quote version"

          argument :quote_version_id, ID, required: true
          argument :plan_id, ID, required: true
          argument :external_subscription_id, String, required: false

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::Plans::AddService.call(
              quote_version:,
              params: args.except(:quote_version_id)
            )
            result.success? ? result.quote_version : result_error(result)
          end
        end
      end
    end
  end
end
