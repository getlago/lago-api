# frozen_string_literal: true

module Agents
  module Claims
    # Gives an enrolled agent a claim code for its owner. One live claim per registration: a new code replaces the
    # previous one.
    class IssueCodeService < BaseService
      Result = BaseResult[:claim, :code]

      def initialize(registration:)
        @registration = registration
        super
      end

      def call
        return result.single_validation_failure!(error_code: "enrollment_required") unless registration.customer

        registration.with_lock do
          # The delete waits for a verification holding one of these rows, and skips the row once it is verified.
          registration.claims.live.delete_all

          if registration.claims.verified.exists?
            result.single_validation_failure!(error_code: "registration_already_claimed")
          else
            code = Agents::Claim.generate_code
            result.claim = registration.claims.create!(organization: registration.organization, code_hash: Agents::Claim.digest(code))
            result.code = code
          end
        end

        result
      end

      private

      attr_reader :registration
    end
  end
end
