# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Mutations
  module PaymentProviders
    module Gocardless
      class Base < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        def resolve(**args)
          result = ::PaymentProviders::GocardlessService
            .new(context[:current_user])
            .create_or_update(**args.merge(organization: current_organization))

          result.success? ? result.gocardless_provider : result_error(result)
        end
      end
    end
  end
end
