# frozen_string_literal: true

module Mutations
  module Signups
    # The user has no organization yet, so no RequiredOrganization and no permission: the service only accepts a
    # self-serve user who still needs one.
    class CreateOrganization < BaseMutation
      include RequiresSelfServeSignup
      include AuthenticableApiUser

      graphql_name "CreateSelfServeOrganization"
      description "Signup Step 3: creates the production organization of a self-serve user, with its sandbox"

      input_object_class Types::Signups::CreateOrganizationInput
      type Types::Signups::CreateOrganizationPayload

      def resolve(name:, role:, source: nil)
        result = ::Signups::CreateOrganizationService.call(
          user: context[:current_user], name:, role:, referral_source: source
        )
        result.success? ? result : result_error(result)
      end
    end
  end
end
