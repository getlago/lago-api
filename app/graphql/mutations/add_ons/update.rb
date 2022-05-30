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
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      type Types::AddOns::Object

      def resolve(**args)
        result = ::AddOns::UpdateService.new(context[:current_user])
          .update(**args)

        result.success? ? result.add_on : result_error(result)
      end
    end
  end
end
