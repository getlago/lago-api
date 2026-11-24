# frozen_string_literal: true

module Agents
  module Claims
    # Issues the code mailed to the owner and replaces the previous one. Only Agents::ClaimMailer#verification calls
    # it, so the clear code never leaves the mailer: no job argument, mailer param or log holds it.
    class IssueVerificationCodeService < BaseService
      Result = BaseResult[:code]

      def initialize(claim:)
        @claim = claim
        super
      end

      def call
        ApplicationRecord.transaction do
          claim.lock!
          code = Agents::Claim.generate_verification_code
          claim.update!(
            verification_code_hash: Agents::Claim.digest(code),
            verification_expires_at: Agents::Claim::VERIFICATION_TTL.from_now
          )
          result.code = code
        end

        result
      end

      private

      attr_reader :claim
    end
  end
end
