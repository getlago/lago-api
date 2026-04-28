# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module AddOns
        class Update < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"

          graphql_name "UpdateQuoteAddOn"
          description "Updates an add-on billing item on a quote version"

          argument :quote_version_id, ID, required: true
          argument :id, ID, required: true
          argument :name, String, required: false
          argument :add_on_id, ID, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :amount_currency, String, required: false
          argument :description, String, required: false

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::AddOns::UpdateService.call(
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
