# frozen_string_literal: true

module AuthenticableUser
  extend ActiveSupport::Concern

  private

  def current_user
    @current_user ||= User.find_by(id: payload_data['sub']) if token && decoded_token && valid_token?
  end

  def token
    @token ||= request.headers['Authorization'].to_s.split(' ').last
  end

  def decoded_token
    @decoded_token ||= JWT.decode(token, Rails.application.secrets.secret_key_base, true, decode_options)
  end

  def valid_token?
    Time.now.to_i <= payload_data['exp']
  end

  def payload_data
    @payload_data ||= decoded_token.reduce({}, :merge)
  end

  def decode_options
    {
      algorithm: 'HS256'
    }
  end
end
