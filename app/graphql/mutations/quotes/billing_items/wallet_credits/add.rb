# frozen_string_literal: true

module Mutations
  module Quotes
    module BillingItems
      module WalletCredits
        class Add < BaseMutation
          include AuthenticableApiUser
          include RequiredOrganization

          REQUIRED_PERMISSION = "quotes:update"
          graphql_name "AddQuoteWalletCredit"
          description "Adds a wallet credit billing item to a draft quote"

          argument :currency, String, required: false
          argument :expiration_at, GraphQL::Types::ISO8601DateTime, required: false
          argument :granted_credits, String, required: false
          argument :name, String, required: false
          argument :paid_credits, String, required: false
          argument :position, Integer, required: false
          argument :priority, Integer, required: false
          argument :quote_id, ID, required: true
          argument :rate_amount, String, required: false
          argument :recurring_transaction_rules, GraphQL::Types::JSON, required: false

          type Types::Quotes::Object

          def resolve(quote_id:, **args)
            quote = current_organization.quotes.find_by(id: quote_id)
            result = ::Quotes::BillingItems::WalletCredits::AddService.call(quote:, params: args)
            result.success? ? result.quote : result_error(result)
          end
        end
      end
    end
  end
end
