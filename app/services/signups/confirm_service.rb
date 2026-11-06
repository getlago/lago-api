# frozen_string_literal: true

module Signups
  # Confirms a verification link and creates the user, with no organization yet. Only the attempt that sent the link can
  # prove it, with its signup secret or its password, so an unsolicited or leaked link creates nothing.
  class ConfirmService < BaseService
    Result = BaseResult[:user, :token]

    REFUSALS = {
      already_verified: "email_already_verified",
      replaced: "signup_token_replaced",
      expired: "signup_token_expired",
      locked: "signup_token_locked"
    }.freeze

    def initialize(token:, signup_secret: nil, password: nil)
      @token = token
      @signup_secret = signup_secret
      @password = password
      super
    end

    def call
      token_record = PendingSignupToken.for_token(token)
      return result.not_found_failure!(resource: "signup_token") unless token_record

      pending_signup = token_record.pending_signup
      by_password = !pending_signup.signup_secret_matches?(signup_secret)
      status = token_record.verification_status(by_password:)
      return refuse(token_record, status:) unless status == :valid

      if by_password
        check_password(token_record, pending_signup)
        return result unless result.success?
      end

      # bcrypt ran above, outside the lock: a public call never holds an address's lock for long.
      user = Users::EmailLockService.call(email: pending_signup.normalized_email) do
        create_user(token_record, pending_signup, by_password:)
      end.value
      return result unless user

      result.user = user
      result.token = Utils::AuthToken.encode(user:, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD)
      # No security log: it needs an organization, which Step 3 creates.
      UserDevices::RegisterService.call!(user:, skip_log: true)
      result
    rescue BaseLockService::FailedToAcquireLock
      result.lock_acquisition_failure!(message: "email lock not acquired")
    end

    private

    attr_reader :token, :signup_secret, :password

    def check_password(token_record, pending_signup)
      return result.single_validation_failure!(field: :password, error_code: "password_required") if password.blank?
      # bcrypt ignores what follows 72 bytes, so such a password was never a Step 1 password.
      return incorrect_password if password.bytesize > ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED
      return refuse(token_record.reload) unless claim_password_try(token_record)

      incorrect_password unless pending_signup.authenticate(password)
    end

    # Counted before bcrypt and committed on its own, so a refused try stays counted, also when Redis is down.
    def claim_password_try(token_record)
      now = Time.current

      PendingSignupToken
        .where(id: token_record.id, status: "pending")
        .where("failed_password_attempts < ? AND expires_at > ?", PendingSignupToken::MAX_PASSWORD_ATTEMPTS, now)
        .update_all(["failed_password_attempts = failed_password_attempts + 1, updated_at = ?", now]) == 1 # rubocop:disable Rails/SkipsModelValidations
    end

    def create_user(token_record, pending_signup, by_password:)
      token_record.lock!
      pending_signup.lock!

      # Another attempt's confirm, an invite or a Google signup may have created the user meanwhile.
      status = token_record.verification_status(by_password:)
      # A password try claimed within the limit stays valid, even when it is the one that reached the limit.
      status = :valid if status == :locked && by_password
      unless status == :valid
        refuse(token_record, status:)
        return
      end

      now = Time.current
      user = User.create!(email: pending_signup.email, password_digest: pending_signup.password_digest, self_serve_verified_at: now)
      token_record.update!(status: :consumed, consumed_at: now)
      pending_signup.update!(verified_at: now, user:, password_digest: nil)
      CloseAttemptsService.call!(normalized_email: pending_signup.normalized_email, except: pending_signup)

      user
    end

    def refuse(token_record, status: token_record.verification_status)
      result.not_allowed_failure!(code: REFUSALS.fetch(status))
    end

    def incorrect_password
      result.single_validation_failure!(field: :password, error_code: "incorrect_password")
    end
  end
end
