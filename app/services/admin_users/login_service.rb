# frozen_string_literal: true

module AdminUsers
  class LoginService < ::BaseService
    Result = BaseResult[:admin_user, :token]

    def initialize(email:, password:)
      @email = email.to_s
      @password = password.to_s

      super
    end

    def call
      if email.include?("\u0000") || password.include?("\u0000")
        return result.single_validation_failure!(error_code: "incorrect_login_or_password")
      end

      admin_user = AdminUser.find_by("LOWER(email) = ?", email.downcase.strip)&.authenticate(password)

      unless admin_user
        return result.single_validation_failure!(error_code: "incorrect_login_or_password")
      end

      admin_user.update_column(:last_sign_in_at, Time.current)

      result.admin_user = admin_user
      result.token = ::Auth::TokenService.encode(user_id: admin_user.id, admin: true)
      result
    end

    private

    attr_reader :email, :password
  end
end
