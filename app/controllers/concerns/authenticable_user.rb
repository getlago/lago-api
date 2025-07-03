# frozen_string_literal: true

module AuthenticableUser
  extend ActiveSupport::Concern

  included do
    before_action :renew_token, if: :expired_token?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: payload_data["sub"]) if token && decoded_token
  end

  def token
    @token ||= request.headers["Authorization"].to_s.split(" ").last
  end

  def decoded_token(verify_exp: true)
    @decoded_token ||= JWT.decode(token, ENV["SECRET_KEY_BASE"], verify_exp, decode_options)
  rescue JWT::DecodeError => e
    raise e if e.is_a?(JWT::ExpiredSignature) || Rails.env.development?
  end

  def expired_token?
    return false unless token && decoded_token(verify_exp: false)

    Time.now.to_i > payload_data["exp"]
  end

  def payload_data
    @payload_data ||= decoded_token.reduce({}, :merge)
  end

  def decode_options
    {
      algorithm: "HS256"
    }
  end

  def renew_token
    return unless current_user

    result = UsersService.new.new_token(current_user)
    response.set_header("x-lago-token", result.token) if result.success?
  end
end
