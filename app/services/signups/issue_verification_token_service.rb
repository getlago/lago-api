# frozen_string_literal: true

module Signups
  # Issues a new link for a signup attempt and replaces its previous one. Only SignupMailer#verification calls it, so
  # the plaintext token never leaves the mailer: no job argument, mailer param or log holds it.
  class IssueVerificationTokenService < BaseService
    Result = BaseResult[:token]

    def initialize(pending_signup:)
      @pending_signup = pending_signup
      super
    end

    def call
      ApplicationRecord.transaction do
        pending_signup.lock!
        now = Time.current

        pending_signup.tokens.pending.update_all(status: "replaced", updated_at: now) # rubocop:disable Rails/SkipsModelValidations
        token = PendingSignupToken.generate
        # A delivery retried after the attempt's window still ends a day after it, as the purge of digests expects.
        expires_at = [now, pending_signup.expires_at].min + PendingSignupToken::TTL
        pending_signup.tokens.create!(token_digest: PendingSignupToken.digest(token), expires_at:)
        result.token = token
      end

      result
    end

    private

    attr_reader :pending_signup
  end
end
