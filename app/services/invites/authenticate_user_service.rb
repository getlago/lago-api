# frozen_string_literal: true

module Invites
  class AuthenticateUserService < BaseService
    Result = BaseResult

    def initialize(user:, password:)
      @user = user
      @password = password.to_s
      super
    end

    def call
      login_method = Organizations::AuthenticationMethods::EMAIL_PASSWORD
      # Users without active memberships can only restore access through an invitation.
      if user.memberships.active.any? && !user.login_method_allowed?(login_method)
        return result.single_validation_failure!(error_code: "login_method_not_authorized", field: login_method)
      end

      if password.include?("\u0000") || !user.authenticate(password)
        result.single_validation_failure!(error_code: "incorrect_login_or_password")
      else
        result
      end
    end

    private

    attr_reader :user, :password
  end
end
