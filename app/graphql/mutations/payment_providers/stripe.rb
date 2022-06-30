# frozen_string_literal: true

module Mutations
  module PaymentProviders
    class Stripe < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'AddStripePaymentProvider'
      description 'Add or update Stripe API keys to the organization'

      argument :secret_key, String, required: false

      argument :create_customers, Boolean, required: false

      type Types::PaymentProviders::Stripe

      def resolve(**args)
        validate_organization!

        result = ::PaymentProviders::StripeService
          .new(context[:current_user])
          .create_or_update(**args.merge(organization_id: current_organization.id))

        result.success? ? result.stripe_provider : result_error(result)
      end
    end
  end
end
