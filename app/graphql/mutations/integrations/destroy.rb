# frozen_string_literal: true

module Mutations
  module Integrations
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:integrations:delete"
      # NOTE: Okta and Entra ID integrations decide who can log in, so deleting one also needs the
      #       permission that manages the authentication methods.
      AUTHENTICATION_METHODS_PERMISSION = "authentication_methods:update"

      graphql_name "DestroyIntegration"
      description "Destroy an integration"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        integration = current_organization.integrations.find_by(id:)
        raise authentication_methods_permission_error if sso_integration?(integration) && !context.dig(:permissions, AUTHENTICATION_METHODS_PERMISSION)

        result = destroy_service(integration:).call(integration:)

        result.success? ? result.integration : result_error(result)
      end

      private

      def sso_integration?(integration)
        integration.is_a?(::Integrations::OktaIntegration) || integration.is_a?(::Integrations::EntraIdIntegration)
      end

      def authentication_methods_permission_error
        GraphQL::ExecutionError.new(
          "Missing permissions",
          extensions: {status: :forbidden, code: "forbidden", required_permissions: [AUTHENTICATION_METHODS_PERMISSION]}
        )
      end

      def destroy_service(integration:)
        case integration
        when ::Integrations::OktaIntegration
          ::Integrations::Okta::DestroyService
        when ::Integrations::EntraIdIntegration
          ::Integrations::EntraId::DestroyService
        else
          ::Integrations::DestroyService
        end
      end
    end
  end
end
