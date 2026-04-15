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
          description "Updates an add-on billing item on a draft quote"

          argument :quote_id, ID, required: true
          argument :id, ID, required: true
          argument :name, String, required: false
          argument :add_on_id, ID, required: false
          argument :description, String, required: false
          argument :units, Integer, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :invoice_display_name, String, required: false
          argument :service_from_date, String, required: false
          argument :service_to_date, String, required: false
          argument :add_on_overrides, GraphQL::Types::JSON, required: false
          argument :position, Integer, required: false

          type Types::Quotes::Object

          def resolve(quote_id:, id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::AddOns::UpdateService.call(quote:, id:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
