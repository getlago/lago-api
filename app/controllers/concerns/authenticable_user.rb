# frozen_string_literal: true

module AuthenticableUser
  extend ActiveSupport::Concern

  included do
    before_action :renew_token, if: :token_near_expiration?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: decoded_token["sub"]) if token && decoded_token
  end

  def login_method
    @login_method ||= decoded_token["login_method"] if token && decoded_token
  end

  def token
    @token ||= request.headers["Authorization"].to_s.split(" ").last
  end

  def decoded_token
    @decoded_token ||= Auth::TokenService.decode(token:)
  rescue JWT::DecodeError => e
    raise e if e.is_a?(JWT::ExpiredSignature) || Rails.env.development?
  end

  def token_near_expiration?
    return false unless token && decoded_token

    # NOTE: we consider the token is near expiration if it expires in less than 1 hour
    Time.now.to_i > payload_data["exp"] - 1.hour.to_i
  end

  def renew_token
    return unless current_user

    renewed = Auth::TokenService.renew(token:)
    response.set_header(Auth::TokenService::LAGO_TOKEN_HEADER, renewed) if renewed.present?
  rescue => e
    Rails.logger.warn("Error renewing token: #{e.message}")
  end
end
