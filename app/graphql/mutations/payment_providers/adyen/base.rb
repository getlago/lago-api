# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Adyen
      class Base < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        def resolve(**args)
          result = ::PaymentProviders::AdyenService
            .new(context[:current_user])
            .create_or_update(**args.merge(organization: current_organization))

          result.success? ? result.adyen_provider : result_error(result)
        end
      end
    end
  end
end
