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
          description "Adds an add-on billing item to a draft quote"

          argument :add_on_id, ID, required: false
          argument :add_on_overrides, GraphQL::Types::JSON, required: false
          argument :amount_cents, GraphQL::Types::BigInt, required: false
          argument :description, String, required: false
          argument :invoice_display_name, String, required: false
          argument :name, String, required: true
          argument :position, Integer, required: false
          argument :quote_id, ID, required: true
          argument :service_from_date, String, required: false
          argument :service_to_date, String, required: false
          argument :units, Integer, required: false

          type Types::Quotes::Object

          def resolve(quote_id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::AddOns::AddService.call(quote:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
