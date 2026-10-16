# frozen_string_literal: true

module Agents
  module Auth
    class VerifyTokenService < BaseService
      Result = BaseResult[:registration]

      def initialize(storefront:, token:)
        @storefront = storefront
        @token = token
        super
      end

      def call
        claims = decode
        return result.unauthorized_failure!(message: "invalid_token") unless claims

        registration = storefront.agent_registrations.find_by(id: claims["sub"])
        return result.unauthorized_failure!(message: "registration_inactive") unless registration&.active?

        result.registration = registration
        result
      end

      private

      attr_reader :storefront, :token

      def decode
        return if token.blank?

        claims, header = JWT.decode(
          token,
          RsaPublicKey,
          true,
          algorithm: "RS256",
          iss: storefront.agent_url,
          verify_iss: true,
          required_claims: %w[sub exp]
        )
        claims if header["typ"] == "at+jwt"
      rescue JWT::DecodeError
        nil
      end
    end
  end
end
