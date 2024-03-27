# frozen_string_literal: true

module PasswordResets
  class ResetService < BaseService
    def initialize(token:, new_password:)
      @token = token
      @new_password = new_password

      super
    end

    def call
      if new_password.blank?
        return result.single_validation_failure!(field: :new_password, error_code: "missing_password")
      end
      return result.single_validation_failure!(field: :token, error_code: "missing_token") if token.blank?

      password_reset = PasswordReset.where("expire_at > ?", Time.current).find_by(token:)

      return result.not_found_failure!(resource: "password_reset") if password_reset.blank?

      ActiveRecord::Base.transaction do
        password_reset.user.password = new_password
        password_reset.user.save!

        result = UsersService.new.login(password_reset.user.email, new_password)

        password_reset.destroy!

        result
      end
    end

    private

    attr_reader :token, :new_password
  end
end
