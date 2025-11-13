# frozen_string_literal: true

module Resolvers
  module Superset
    class TokenResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "SupersetToken"
      description "Query Superset for the Auth Token"

      argument :dashboardId, Integer, required: true

      type Types::Superset::Token::Object, null: true

      def resolve(**args)
        result = SupersetAuthService.call(
          organization: current_organization,
          dashboard_id: params[:dashboard_id],
          user: user_params
        )
        {
          guest_token: result.guest_token,
          access_token: result.access_token
        }
      end
    end
  end
end
  