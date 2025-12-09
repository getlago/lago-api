# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Braintree
      class Base < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        def resolve(**args)
          result = ::PaymentProviders::BraintreeService
            .new(context[:current_user])
            .create_or_update(**args.merge(organization: current_organization))

          result.success? ? result.braintree_provider : result_error(result)
        end
      end
    end
  end
end
