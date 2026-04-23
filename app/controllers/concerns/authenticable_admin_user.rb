# frozen_string_literal: true

module AuthenticableAdminUser
  extend ActiveSupport::Concern

  private

  def current_admin_user
    return @current_admin_user if defined?(@current_admin_user)
    return (@current_admin_user = nil) unless admin_token?

    email = admin_decoded_token["sub"]
    @current_admin_user = AdminStaffCredentials.find(email)
  end

  def admin_token?
    admin_decoded_token.is_a?(Hash) && admin_decoded_token["admin"] == true
  end

  def admin_decoded_token
    @admin_decoded_token ||= begin
      raw = request.headers["Authorization"].to_s.split(" ").last
      Auth::TokenService.decode(token: raw) if raw.present?
    rescue JWT::DecodeError
      nil
    end
  end
end
