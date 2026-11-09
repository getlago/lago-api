# frozen_string_literal: true

module Signups
  # Signs up with a company Google account, which Google verified, so no email is sent and the user goes to Step 3.
  # A personal or unverified account creates nothing; an address that has a user logs in under the Google login rules.
  class CreateWithGoogleService < BaseService
    Result = BaseResult[:user, :token]

    def initialize(code:, state:, state_secret:)
      @code = code
      @state = state
      @state_secret = state_secret
      super
    end

    def call
      return result.forbidden_failure!(code: "self_serve_disabled") unless Lago::SelfServe.enabled?
      return result.forbidden_failure!(code: "signup_disabled") if Lago::SelfServe.signup_disabled?

      claims_result = ::Auth::GoogleService.call(:claims, code, state:, state_secret:)
      return result.fail_with_error!(claims_result.error) unless claims_result.success?

      claims = claims_result.claims
      email = claims["email"].to_s
      user = Users::EmailLockService.call(email:) { find_or_create_user(claims, email) }.value
      return result unless user

      result.user = user
      result.token = Utils::AuthToken.encode(user:, login_method: Organizations::AuthenticationMethods::GOOGLE_OAUTH)
      UserDevices::RegisterService.call!(user:, skip_log: created)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseLockService::FailedToAcquireLock
      result.lock_acquisition_failure!(message: "email lock not acquired")
    end

    private

    attr_reader :code, :state, :state_secret, :created

    # Under the email lock, so a concurrent confirm, invite or second tab sees the committed user.
    def find_or_create_user(claims, email)
      user = User.lookup_by_email(email)

      if user
        user unless login_refused?(user, claims)
      else
        create_user(claims, email)
      end
    end

    def create_user(claims, email)
      validation = ValidateEmailService.call(email:)
      # Only a new user needs Google's verification here: an existing one logs in under the Google login rules.
      unless ::Auth::GoogleLoginRules.email_verified?(claims) && workspace_account?(claims, validation)
        company_account_required
        return
      end

      @created = true
      user = User.create!(email: validation.email, password: SecureRandom.hex, self_serve_verified_at: Time.current)
      # Never verifies or links a pending email signup: whoever ran that Step 1 could then exchange its secret for
      # this user's session. Its links stop working and its password digest is dropped.
      CloseAttemptsService.call!(normalized_email: PendingSignup.normalize_email(validation.email))
      user
    end

    def login_refused?(user, claims)
      refusal = ::Auth::GoogleLoginRules.refusal(user, claims)
      result.single_validation_failure!(**refusal) if refusal
      result.failure?
    end

    # A Workspace account (hd) on a company domain: a consumer Google account on a work address can outlive the job.
    # Google sets hd only for addresses on a domain the Workspace verified, so its subdomains and secondary domains
    # count too, and the address still has to pass the company domain policy.
    def workspace_account?(claims, validation)
      validation.success? && claims["hd"].is_a?(String) && claims["hd"].present?
    end

    def company_account_required
      result.single_validation_failure!(error_code: "company_google_account_required")
    end
  end
end
