# frozen_string_literal: true

module Mutations
  module PaymentProviders
    class Adyen < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'AddAdyenPaymentProvider'
      description 'Add or update Adyen payment provider'

      argument :api_key, String, required: true
      argument :merchant_account, String, required: true
      argument :live_prefix, String, required: false
      argument :hmac_key, String, required: false

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
