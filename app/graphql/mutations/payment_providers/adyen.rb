# frozen_string_literal: true

module Mutations
  module PaymentProviders
    class Adyen < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'AddAdyenPaymentProvider'
      description 'Add or update Adyen payment provider'

      input_object_class Types::PaymentProviders::AdyenInput

      type Types::PaymentProviders::Adyen

      def resolve(**args)
        validate_organization!

        result = ::PaymentProviders::AdyenService
          .new(context[:current_user])
          .create_or_update(**args.merge(organization: current_organization))

        result.success? ? result.adyen_provider : result_error(result)
      end
    end
  end
end
