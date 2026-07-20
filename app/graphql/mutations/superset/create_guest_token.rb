# frozen_string_literal: true

module Mutations
  module Superset
    class CreateGuestToken < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      graphql_name "CreateSupersetGuestToken"
      description "Mint a fresh Superset guest token for a single dashboard"

      argument :dashboard_id, ID, required: true

      type Types::Superset::GuestToken::Object

      def resolve(dashboard_id:)
        result = ::Auth::Superset::GuestTokenService.call(
          organization: current_organization,
          dashboard_id:,
          user: nil
        )

        result.success? ? {guest_token: result.guest_token} : result_error(result)
      end
    end
  end
end
