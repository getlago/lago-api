# frozen_string_literal: true

module Agents
  module Claims
    # The owner typed the agent's claim code and an e-mail: keeps the address until it is verified and mails the code.
    class StartService < BaseService
      Result = BaseResult[:claim]

      MAX_EMAIL_LENGTH = 254

      def initialize(storefront:, params:)
        @storefront = storefront
        @params = params
        super
      end

      def call
        return invalid_claim_code unless claim
        return result.single_validation_failure!(error_code: "registration_inactive") unless claim.registration.active?
        return result.single_validation_failure!(field: :email, error_code: "invalid_email_format") unless valid_email?
        # Counted once the code is good, so bogus codes sent with someone's address cannot use up their mailbox budget.
        return result.not_allowed_failure!(code: "too_many_requests") if mailbox_throttled?

        claim.with_lock do
          # Verified since it was loaded: the claim is spent.
          next invalid_claim_code if claim.verified?

          claim.update!(email:, status: :started)
        end
        return result unless result.success?

        Agents::ClaimMailer.with(claim_id: claim.id).verification.deliver_later
        result.claim = claim
        result
      rescue ActiveRecord::RecordNotFound
        # The agent asked for a new code meanwhile, which deleted this claim.
        invalid_claim_code
      end

      private

      attr_reader :storefront, :params

      def claim
        @claim ||= Agents::Claim.live.where(registration: storefront.agent_registrations).for_code(params[:claim_code])
      end

      def invalid_claim_code
        result.single_validation_failure!(field: :claim_code, error_code: "invalid_claim_code")
      end

      def email
        @email ||= EmailSanitizer.call(params[:email].to_s).to_s
      end

      # One address: the customer validator also takes comma-separated lists, which a claim never does.
      def valid_email?
        email.length <= MAX_EMAIL_LENGTH && email.count("@") == 1 && Regex::EMAIL.match?(email)
      end

      # Per mailbox, as the signup mails are: addresses that differ only by a +tag share the budget.
      def mailbox_throttled?
        ::Auth::AttemptsThrottle.hit!(:agent_claim_mail_per_email, Signups::ValidateEmailService.mailbox_key(email))
      end
    end
  end
end
