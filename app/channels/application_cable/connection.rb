# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # The token comes as a Sec-WebSocket-Protocol entry: unlike the URL and channel params, Rails does not log it.
    TOKEN_SUBPROTOCOL_PREFIX = "lago-token."
    PROTOCOL_HEADER = "HTTP_SEC_WEBSOCKET_PROTOCOL"

    identified_by :connection_identifier

    attr_reader :current_user, :auth_error_code

    def connect
      token = subprotocol_token
      # The handshake is already answered, and Sentry reads this env when reporting channel errors.
      redact_token_from_env

      self.connection_identifier = SecureRandom.uuid
      authenticate_user(token)
      # No socket without a valid session: an Origin header is not a credential outside a browser.
      reject_unauthorized_connection unless current_user
    end

    def session_claims
      @session_claims || {}
    end

    # Authenticated once, when the socket opens: past expiry, a new subscription makes the client reconnect
    # and stream updates end their subscription.
    def token_expired?
      @token_expires_at.present? && Time.current.to_i >= @token_expires_at
    end

    private

    def authenticate_user(token)
      decoded_token = Utils::AuthToken.decode(token:)
      return unless decoded_token
      return if Utils::AuthToken.sso_session_without_claims?(decoded_token)

      @current_user = User.find_by(id: decoded_token["sub"])
      @token_expires_at = decoded_token["exp"]
      @session_claims = Utils::AuthToken.session_claims(decoded_token)
    rescue JWT::ExpiredSignature
      @auth_error_code = "expired_jwt_token"
    rescue JWT::DecodeError
      @current_user = nil
    end

    def offered_protocols
      env[PROTOCOL_HEADER].to_s.split(",").map(&:strip)
    end

    def subprotocol_token
      offered_protocols
        .find { |protocol| protocol.start_with?(TOKEN_SUBPROTOCOL_PREFIX) }
        &.delete_prefix(TOKEN_SUBPROTOCOL_PREFIX)
    end

    def redact_token_from_env
      return if env[PROTOCOL_HEADER].blank?

      env[PROTOCOL_HEADER] = offered_protocols.map do |protocol|
        protocol.start_with?(TOKEN_SUBPROTOCOL_PREFIX) ? "#{TOKEN_SUBPROTOCOL_PREFIX}[FILTERED]" : protocol
      end.join(", ")
    end
  end
end
