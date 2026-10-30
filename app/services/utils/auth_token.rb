# frozen_string_literal: true

module Utils
  class AuthToken
    THREE_HOURS = 10800
    ALGORITHM = "HS256"
    LAGO_TOKEN_HEADER = "x-lago-token"
    SESSION_CLAIMS = %w[login_method sso_organization_id sso_issuer].freeze

    def self.encode(user: nil, user_id: nil, **extra)
      return nil if (user_id || user&.id).blank?

      JWT.encode(payload(user:, user_id:, **extra), ENV["SECRET_KEY_BASE"], ALGORITHM)
    end

    def self.decode(token:)
      return nil if token.blank?

      JWT.decode(token, ENV["SECRET_KEY_BASE"], true, {algorithm: ALGORITHM}).reduce({}, :merge)
    end

    def self.session_claims(decoded_token)
      decoded_token.slice(*SESSION_CLAIMS).symbolize_keys
    end

    # NOTE: Okta and Entra ID sessions issued before the SSO claims existed cannot be tied to an
    #       identity provider, so they are treated as expired and the user logs in again.
    def self.sso_session_without_claims?(decoded_token)
      Organizations::AuthenticationMethods::SSO_INTEGRATION_TYPES.key?(decoded_token["login_method"]) &&
        decoded_token["sso_organization_id"].blank?
    end

    def self.renew(token:)
      return nil if token.blank?

      decoded = decode(token:)
      user_id = decoded["sub"]
      extra = decoded.except(*non_extra_attributes)

      encode(user_id:, **extra)
    end

    def self.non_extra_attributes
      ["sub", "exp", "alg"]
    end

    def self.payload(user: nil, user_id: nil, **extra)
      {
        sub: user_id || user.id,
        exp: Time.current.to_i + THREE_HOURS
      }.merge(extra)
    end

    private_class_method :non_extra_attributes, :payload
  end
end
