# frozen_string_literal: true

module Mutations
  module PaymentProviders
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name "DestroyPaymentProvider"
      description "Destroy a payment provider"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ::PaymentProviders::DestroyService
          .new(context[:current_user])
          .destroy(id:)

        result.success? ? result.payment_provider : result_error(result)
      end
    end
  end
end
