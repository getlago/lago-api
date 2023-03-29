# frozen_string_literal: true

module PasswordReset
  class CreateService < BaseService
    def initialize(user:)
      @user = user

      super
    end

    def call
      return result.not_found_failure!(resource: 'user') if user.blank?

      password_reset = PasswordReset.create!(
        user_id: user.id,
        token: SecureRandom.hex(20),
        expire_at: DateTime.now + 30.minutes,
      )

      PasswordResetMailer.with(password_reset:).requested.deliver_later

      result.id = password_reset.id

      result
    end

    private

    attr_reader :user
  end
end
