# frozen_string_literal: true

module Agents
  module Claims
    # The owner typed the mailed code: the claim is verified and the agent's customer gets the e-mail, in one
    # transaction, so a claimed agent always has its owner's e-mail.
    class VerifyService < BaseService
      Result = BaseResult[:claim]

      def initialize(storefront:, params:)
        @storefront = storefront
        @params = params
        super
      end

      def call
        return invalid_claim_code unless claim
        return result.single_validation_failure!(error_code: "registration_inactive") unless claim.registration.active?

        claim.with_lock do
          # Another browser may have verified it first.
          next invalid_claim_code unless claim.started?
          next result.single_validation_failure!(field: :verification_code, error_code: "verification_expired") if claim.verification_expired?
          next result.single_validation_failure!(field: :verification_code, error_code: "invalid_verification_code") unless verification_code_matches?

          customer = claim.registration.customer
          next result.single_validation_failure!(error_code: "enrollment_required") unless customer

          # The owner edits the customer's own e-mail, as the customer portal lets a customer do; the merchant is told.
          customer.update!(email: claim.email)
          claim.update!(status: :verified, verified_at: Time.current, email: nil)
          SendWebhookJob.perform_after_commit("customer.updated", customer)
          Utils::ActivityLog.produce_after_commit(customer, "customer.updated")
          Customers::RefreshInvoicesSearchTermsJob.perform_after_commit(customer.id)
        end
        return result unless result.success?

        result.claim = claim
        result
      rescue ActiveRecord::RecordNotFound
        # The agent asked for a new code meanwhile, which deleted this claim.
        invalid_claim_code
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :storefront, :params

      def claim
        @claim ||= Agents::Claim.started.where(registration: storefront.agent_registrations).for_code(params[:claim_code])
      end

      def invalid_claim_code
        result.single_validation_failure!(field: :claim_code, error_code: "invalid_claim_code")
      end

      def verification_code_matches?
        return false if claim.verification_code_hash.blank?

        typed = params[:verification_code].to_s.gsub(/\D/, "")
        ActiveSupport::SecurityUtils.secure_compare(claim.verification_code_hash, Agents::Claim.digest(typed))
      end
    end
  end
end
