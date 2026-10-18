# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Browsers cannot set headers on a websocket, so the front end sends the user token as an
    # extra Sec-WebSocket-Protocol entry. Rails does not log that header, unlike the URL and
    # the channel identifier.
    TOKEN_SUBPROTOCOL_PREFIX = "lago-token."

    identified_by :connection_identifier

    attr_reader :current_user, :auth_error_code

    def connect
      self.connection_identifier = SecureRandom.uuid
      authenticate_user
    end

    private

    def authenticate_user
      decoded_token = Utils::AuthToken.decode(token: subprotocol_token)
      @current_user = User.find_by(id: decoded_token["sub"]) if decoded_token
    rescue JWT::ExpiredSignature
      @auth_error_code = "expired_jwt_token"
    rescue JWT::DecodeError
      @current_user = nil
    end

    def subprotocol_token
      request.headers["Sec-WebSocket-Protocol"].to_s.split(",").map(&:strip)
        .find { |protocol| protocol.start_with?(TOKEN_SUBPROTOCOL_PREFIX) }
        &.delete_prefix(TOKEN_SUBPROTOCOL_PREFIX)
    end
  end
end
