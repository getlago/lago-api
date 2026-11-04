# frozen_string_literal: true

module Signups
  # Step 1 of the self-serve signup: stores an attempt and sends its email from a job. It never looks users up and does
  # the same work for every address, so its answer and timing never tell whether the address has an account.
  class CreateService < BaseService
    Result = BaseResult[:signup_secret]

    def initialize(email:, password:)
      @email = email
      @password = password
      super
    end

    def call
      validation = ValidateEmailService.call(email:)
      errors = input_errors(validation)
      return result.validation_failure!(errors:) if errors.any?

      mailbox_key = validation.mailbox_key
      return too_many_requests if PendingSignup.mailbox_send_refusal(mailbox_key, Time.current) || mailbox_throttled?(mailbox_key)

      # Hashed only now, after every limit and check, so bcrypt cannot be used to exhaust the CPU.
      password_digest = PendingSignup.digest_password(password)
      secret = PendingSignup.generate_signup_secret

      created = Users::EmailLockService.call(email: validation.email) do
        now = Time.current
        # Authoritative: the database history holds when the throttling Redis is down.
        next false if PendingSignup.mailbox_send_refusal(mailbox_key, now)

        pending_signup = PendingSignup.create!(
          email: User.normalize_value_for(:email, email),
          normalized_email: PendingSignup.normalize_email(validation.email),
          mailbox_key:,
          password_digest:,
          signup_secret_digest: PendingSignup.digest_signup_secret(secret),
          expires_at: now + PendingSignup::RESEND_WINDOW,
          emails_sent_at: [now]
        )
        DeliverVerificationJob.perform_after_commit(pending_signup.id)
        true
      end.value
      return too_many_requests unless created

      result.signup_secret = secret
      result
    rescue BaseLockService::FailedToAcquireLock
      result.lock_acquisition_failure!(message: "email lock not acquired")
    end

    private

    attr_reader :email, :password

    def input_errors(validation)
      password_errors = password.blank? ? ["value_is_mandatory"] : PasswordPolicy.violations(password)

      {email: validation.error&.messages&.dig(:email), password: password_errors.presence}.compact
    end

    # The hourly budget is hit only when the minute one passed, so a refused double click does not use it up.
    def mailbox_throttled?(mailbox_key)
      Auth::AttemptsThrottle.hit!(:signup_email_per_minute, mailbox_key) ||
        Auth::AttemptsThrottle.hit!(:signup_email_per_hour, mailbox_key)
    end

    def too_many_requests
      result.not_allowed_failure!(code: "too_many_requests")
    end
  end
end
