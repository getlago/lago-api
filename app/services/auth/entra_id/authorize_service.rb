# frozen_string_literal: true

require "redis"

module Auth
  module EntraId
    class AuthorizeService < BaseService
      def initialize(email:, invite_token: nil)
        @email = email
        @invite_token = invite_token
        initialize_state

        super
      end

      def call
        check_invite(email) if invite_token.present?
        check_entra_id_integration(email)

        params = {
          client_id: result.entra_id_integration.client_id,
          response_type: "code",
          response_mode: "query",
          scope: "openid profile email",
          redirect_uri: "#{ENV["LAGO_FRONT_URL"]}/auth/entra/callback",
          state:
        }
        result.url = URI::HTTPS.build(
          host: result.entra_id_integration.host,
          path: "/#{result.entra_id_integration.tenant_id}/oauth2/v2.0/authorize",
          query: params.to_query
        ).to_s

        result
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
        result
      end

      private

      attr_reader :email, :invite_token

      def initialize_state
        Rails.cache.write(state, email, expires_in: 90.seconds)
      end

      def state
        @state ||= SecureRandom.uuid
      end
    end
  end
end
