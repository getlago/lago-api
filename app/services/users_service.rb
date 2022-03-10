# frozen_string_literal: true

class UsersService < BaseService
  def login(email, password)
    result.user = User.find_by(email: email)&.authenticate(password)
    result.token = generate_token if result.user
    result.fail!('incorrect_login_or_password') unless result.user

    result
  end

  def register(email, password, organization_name)
    result.user = User.find_or_initialize_by(email: email)

    if result.user.id
      result.fail!('user_already_exists')

      return result
    end

    ActiveRecord::Base.transaction do
      result.organization = Organization.create!(name: organization_name)
      result.user.password = password
      result.user.save!
      result.token = generate_token

      result.membership = Membership.create!(
        user: result.user,
        organization: result.organization,
        role: :admin
      )
    end

    result
  end

  def new_token(user)
    result.user = user
    result.token = generate_token
    result
  end

  private

  def generate_token
    JWT.encode(payload, Rails.application.secrets.secret_key_base, 'HS256')
  rescue StandardError => e
    result.fail!('token_encoding_error', e.message)
  end

  def payload
    {
      sub: result.user.id,
      exp: Time.now.to_i + 8640 # 6 hours expiration
    }
  end
end
