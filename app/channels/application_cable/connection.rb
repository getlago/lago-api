# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Browsers cannot set headers on a websocket, so the front end sends the user token as an
    # extra Sec-WebSocket-Protocol entry. Rails does not log that header, unlike the URL and
    # the channel identifier.
    TOKEN_SUBPROTOCOL_PREFIX = "lago-token."
    PROTOCOL_HEADER = "HTTP_SEC_WEBSOCKET_PROTOCOL"

    identified_by :connection_identifier

    attr_reader :current_user, :auth_error_code

    def connect
      token = subprotocol_token
      # The handshake is answered before connect runs, so the header is no longer needed.
      # Error trackers such as Sentry read it from this env when reporting channel errors.
      redact_token_from_env

      self.connection_identifier = SecureRandom.uuid
      authenticate_user(token)
    end

    # The connection is authenticated once, when the socket opens. Past the token expiration,
    # GraphqlChannel closes the socket and the client reopens it with its renewed token.
    def token_expired?
      @token_expires_at.present? && Time.current.to_i >= @token_expires_at
    end

    private

    def authenticate_user(token)
      decoded_token = Utils::AuthToken.decode(token:)
      return unless decoded_token

      @current_user = User.find_by(id: decoded_token["sub"])
      @token_expires_at = decoded_token["exp"]
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
