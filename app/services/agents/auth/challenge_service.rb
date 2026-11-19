# frozen_string_literal: true

module Agents
  module Auth
    class ChallengeService < BaseService
      PROTOCOL = "lago-agent-auth-v1"
      PURPOSES = %w[signup authenticate revoke].freeze
      TTL = 120.seconds

      Result = BaseResult[:challenge_id, :message, :expires_at]

      def self.cache_key(challenge_id)
        "agents:challenge:#{challenge_id}"
      end

      def self.decode(value, bytesize)
        return unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]+\z/)

        bytes = Base64.urlsafe_decode64(value)
        bytes if bytes.bytesize == bytesize && Base64.urlsafe_encode64(bytes, padding: false) == value
      rescue ArgumentError
        nil
      end

      def self.key_id(raw_public_key)
        Base64.urlsafe_encode64(Digest::SHA256.digest(raw_public_key), padding: false)
      end

      def initialize(storefront:, public_key:, purpose:)
        @storefront = storefront
        @public_key = public_key
        @purpose = purpose
        super
      end

      def call
        raw_public_key = self.class.decode(public_key, 32)
        return result.single_validation_failure!(field: :public_key, error_code: "value_is_invalid") unless raw_public_key
        return result.single_validation_failure!(field: :purpose, error_code: "value_is_invalid") unless PURPOSES.include?(purpose)

        challenge_id = SecureRandom.uuid
        issued_at = Time.current.to_i
        expires_at = issued_at + TTL.to_i
        key_id = self.class.key_id(raw_public_key)

        message = JSON.generate(
          challenge_id:,
          expires_at:,
          issued_at:,
          issuer: storefront.agent_url,
          key_fingerprint: key_id,
          nonce: SecureRandom.urlsafe_base64(32),
          protocol: PROTOCOL,
          purpose:
        )

        Rails.cache.write(
          self.class.cache_key(challenge_id),
          {storefront_id: storefront.id, public_key:, key_id:, purpose:, message:, expires_at:},
          expires_in: TTL
        )

        result.challenge_id = challenge_id
        result.message = message
        result.expires_at = expires_at
        result
      end

      private

      attr_reader :storefront, :public_key, :purpose
    end
  end
end
