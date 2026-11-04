# frozen_string_literal: true

module Signups
  # Opens a session in the tab that started a signup, once its link was confirmed in another tab or on another
  # device. Works once, within an hour of the confirmation.
  class ExchangeSecretService < BaseService
    Result = BaseResult[:user, :token]

    def initialize(signup_secret:)
      @signup_secret = signup_secret
      super
    end

    def call
      pending_signup = PendingSignup.for_signup_secret(signup_secret)
      return result.not_found_failure!(resource: "signup_secret") unless pending_signup
      return result.not_allowed_failure!(code: "email_not_verified") unless pending_signup.verified?
      return result.not_allowed_failure!(code: "signup_secret_expired") unless claim_exchange(pending_signup)

      # The user this attempt's confirm created, never a user found by email.
      result.user = pending_signup.user
      result.token = Utils::AuthToken.encode(user: result.user, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD)
      UserDevices::RegisterService.call!(user: result.user, skip_log: true)
      result
    end

    private

    attr_reader :signup_secret

    # The consumed link is a second marker that only Signups::ConfirmService writes: an attempt marked verified any
    # other way is never exchangeable.
    def claim_exchange(pending_signup)
      now = Time.current

      PendingSignup
        .where(id: pending_signup.id, signup_secret_exchanged_at: nil, verified_at: (now - PendingSignup::SECRET_EXCHANGE_WINDOW)..)
        .where.not(user_id: nil)
        .where(id: PendingSignupToken.consumed.select(:pending_signup_id))
        .update_all(signup_secret_exchanged_at: now, updated_at: now) == 1 # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
