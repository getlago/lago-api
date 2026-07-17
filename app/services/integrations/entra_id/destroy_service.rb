# frozen_string_literal: true

module Integrations
  module EntraId
    class DestroyService < Integrations::DestroyService
      def call
        return result.not_found_failure!(resource: "integration") unless integration
        return result.not_allowed_failure!(code: "enabled_authentication_methods_required") unless can_destroy?

        ActiveRecord::Base.transaction do
          result = super

          if result.success?
            organization = result.integration.organization
            organization.disable_entra_id_authentication! if organization.entra_id_authentication_enabled?
          end

          result
        end
      end

      private

      def can_destroy?
        (integration.organization.authentication_methods - [Organizations::AuthenticationMethods::ENTRA_ID]).size >= 1
      end
    end
  end
end
