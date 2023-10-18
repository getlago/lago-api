# frozen_string_literal: true

module Mutations
  module PaymentProviders
    class Gocardless < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'AddGocardlessPaymentProvider'
      description 'Add or update Gocardless payment provider'

      input_object_class Types::PaymentProviders::GocardlessInput

      type Types::PaymentProviders::Gocardless

      def resolve(**args)
        validate_organization!

        result = ::PaymentProviders::GocardlessService
          .new(context[:current_user])
          .create_or_update(**args.merge(organization: current_organization))

        result.success? ? result.gocardless_provider : result_error(result)
      end
    end
  end
end
