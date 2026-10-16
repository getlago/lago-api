# frozen_string_literal: true

module Agents
  module Auth
    class ProofService < BaseService
      TOKEN_TTL = 300.seconds

      Result = BaseResult[:registration, :created, :access_token]

      def initialize(storefront:, challenge_id:, signature:, purpose:)
        @storefront = storefront
        @challenge_id = challenge_id
        @signature = signature
        @purpose = purpose
        super
      end

      def call
        raw_signature = ChallengeService.decode(signature, 64)
        return result.single_validation_failure!(field: :signature, error_code: "value_is_invalid") unless raw_signature

        challenge = Rails.cache.read(cache_key) if challenge_id.is_a?(String)
        return result.unauthorized_failure!(message: "invalid_or_expired_challenge") unless valid_challenge?(challenge)
        return result.unauthorized_failure!(message: "invalid_proof") unless verified?(challenge, raw_signature)

        registration = storefront.agent_registrations.find_by(key_id: challenge[:key_id])
        return result.forbidden_failure!(code: "registration_revoked") if registration&.revoked?
        return result.unauthorized_failure!(message: "registration_required") if registration.nil? && purpose != "signup"
        return result.unauthorized_failure!(message: "invalid_or_expired_challenge") unless Rails.cache.delete(cache_key)

        result.created = registration.nil?
        registration ||= create_registration(challenge)

        if purpose == "revoke"
          registration.update!(status: :revoked, revoked_at: Time.current)
        else
          registration.update!(last_authenticated_at: Time.current)
          result.access_token = access_token(registration)
        end

        result.registration = registration
        result
      end

      private

      attr_reader :storefront, :challenge_id, :signature, :purpose

      def cache_key
        ChallengeService.cache_key(challenge_id)
      end

      def valid_challenge?(challenge)
        challenge.present? &&
          challenge[:storefront_id] == storefront.id &&
          challenge[:purpose] == purpose &&
          challenge[:expires_at] > Time.current.to_i
      end

      def verified?(challenge, raw_signature)
        raw_public_key = ChallengeService.decode(challenge[:public_key], 32)
        OpenSSL::PKey.new_raw_public_key("ED25519", raw_public_key).verify(nil, raw_signature, challenge[:message])
      rescue OpenSSL::PKey::PKeyError
        false
      end

      def create_registration(challenge)
        storefront.agent_registrations.create!(
          organization_id: storefront.organization_id,
          key_id: challenge[:key_id],
          public_key: challenge[:public_key]
        )
      rescue ActiveRecord::RecordNotUnique
        result.created = false
        storefront.agent_registrations.find_by!(key_id: challenge[:key_id])
      end

      def access_token(registration)
        issued_at = Time.current.to_i

        JWT.encode(
          {
            iss: storefront.agent_url,
            sub: registration.id,
            scope: storefront.scope,
            iat: issued_at,
            nbf: issued_at,
            exp: issued_at + TOKEN_TTL.to_i,
            jti: SecureRandom.uuid
          },
          RsaPrivateKey,
          "RS256",
          {typ: "at+jwt"}
        )
      end
    end
  end
end
