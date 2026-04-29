# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module AddOns
        class Add < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"

          graphql_name "AddQuoteAddOn"
          description "Adds an add-on billing item to a quote version"

          argument :quote_version_id, ID, required: true
          argument :name, String, required: true
          argument :add_on_id, ID, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :amount_currency, String, required: false
          argument :description, String, required: false

          type Types::QuoteVersions::Object

          def resolve(**args)
            quote_version = current_organization.quote_versions.find_by(id: args[:quote_version_id])
            result = ::Quotes::BillingItems::AddOns::AddService.call(
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
