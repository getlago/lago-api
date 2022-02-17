# frozen_string_literal: true

class UsersService < BaseService
  def login(email, password)
    result.user = User.find_by(email: email)&.authenticate(password)
    result.token = generate_token if result.user
    result.fail!('incorrect_login_or_password') unless result.user

    result
  end

  private

  def generate_token
    JWT.encode(payload, Rails.application.secrets.secret_key_base, 'HS256')
  rescue StandardError => e
    result.fail!(e.message)
  end

  def payload
    {
      sub: result.user.id,
      exp: Time.now.to_i + 8640 # 6 hours expiration
    }
  end
end
