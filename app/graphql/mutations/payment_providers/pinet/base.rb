# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Pinet
      class Base < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        def resolve(**args)
          validate_organization!

          result = ::PaymentProviders::PinetService
            .new(context[:current_user])
            .create_or_update(**args.merge(organization_id: current_organization.id))

          result.success? ? result.pinet_provider : result_error(result)
        end
      end
    end
  end
end
