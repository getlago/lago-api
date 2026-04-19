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
          description "Adds a plan billing item to a draft quote"

          argument :entitlements_overrides, GraphQL::Types::JSON, required: false
          argument :plan_code, String, required: false
          argument :plan_description, String, required: false
          argument :plan_id, ID, required: true
          argument :plan_name, String, required: false
          argument :plan_overrides, GraphQL::Types::JSON, required: false
          argument :position, Integer, required: false
          argument :quote_id, ID, required: true
          argument :subscription_external_id, String, required: false

          type Types::Quotes::Object

          def resolve(quote_id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::Plans::AddService.call(quote:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
