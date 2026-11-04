# frozen_string_literal: true

module Signups
  # The state of a verification link, for the page it opens. Read-only, so mail scanners that render the page change
  # nothing.
  class TokenStatusService < BaseService
    Result = BaseResult[:status, :email, :password_required]

    def initialize(token:, signup_secret: nil)
      @token = token
      @signup_secret = signup_secret
      super
    end

    def call
      token_record = PendingSignupToken.for_token(token)
      pending_signup = token_record&.pending_signup

      result.status = token_record ? token_record.verification_status : :invalid
      result.email = pending_signup.email if result.status == :valid
      # Without the secret of the attempt that sent the link (another device, or an earlier signup), the page asks
      # for that attempt's password.
      result.password_required = !pending_signup&.signup_secret_matches?(signup_secret)
      result
    end

    private

    attr_reader :token, :signup_secret
  end
end
