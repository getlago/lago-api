# frozen_string_literal: true

module Mutations
  module AddOns
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateAddOn'
      description 'Update an existing add-on'

      argument :id, ID, required: true
      argument :name, String, required: true
      argument :code, String, required: true
      argument :description, String, required: false
      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      type Types::AddOns::Object

      def resolve(**args)
        add_on = context[:current_user].add_ons.find_by(id: args[:id])
        result = ::AddOns::UpdateService.call(add_on:, params: args)

        result.success? ? result.add_on : result_error(result)
      end
    end
  end
end
