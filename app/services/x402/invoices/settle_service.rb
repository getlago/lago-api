# frozen_string_literal: true

module X402
  module Invoices
    class SettleService < BaseService
      Result = BaseResult[:settlement]
      RACE_CODES = %w[payment_already_recorded invoice_payment_pending].freeze

      def initialize(invoice:, payment:)
        @invoice = invoice
        @payment = payment

        super
      end

      def call
        return refuse(:payment, "invalid_payment") unless payment.is_a?(Hash)

        replay = find_replay
        return answer_replay(replay) if replay

        challenge = X402::Invoices::GenerateChallengeService.call(invoice:)
        return result.fail_with_error!(challenge.error) if challenge.failure?

        requirement = payment_requirement(challenge.requirements)
        return refuse(:payment_requirements, "unsupported_network") unless requirement

        verified_payment = verify(requirement)

        if verified_payment
          settle(verified_payment)
        else
          result
        end
      end

      private

      attr_reader :invoice, :payment

      def connection
        invoice.x402_connection
      end

      def find_replay
        invoice.x402_settlements.settled.find do |settlement|
          X402::Payments::ComputeDigestService.call(payment:, network: settlement.network, asset: settlement.asset).digest == settlement.payment_digest
        end
      end

      def payment_requirement(requirements)
        accepted = payment["accepted"]
        return unless accepted.is_a?(Hash)

        entry = requirements.find { |requirement| requirement[:network] == accepted["network"] }
        return unless entry

        requirement = X402::Wire::V2Codec.requirement(entry)

        if X402::Network.family_of_network(entry[:network]) == :svm && accepted["extra"].is_a?(Hash)
          requirement.merge("extra" => {"feePayer" => accepted["extra"]["feePayer"]})
        else
          requirement
        end
      end

      def reset_envelope
        reset = payment.merge("resource" => X402::Wire::V2Codec.invoice_resource(invoice))
        extensions = payment["extensions"]

        if extensions.is_a?(Hash)
          reset.merge("extensions" => extensions.except("bazaar"))
        else
          reset
        end
      end

      def verify(requirement)
        verification = X402::Settlements::VerifyService.call(connection:, payment: reset_envelope, payment_requirements: requirement)
        return verification.verified_payment if verification.success?

        result.fail_with_error!(verification.error)
        nil
      rescue X402::Facilitator::Error => e
        reason = e.class.name.demodulize.underscore
        result.third_party_failure!(third_party: connection.facilitator, error_code: reason, error_message: "#{reason}: #{e.message}")
        nil
      end

      def settle(verified_payment)
        settle_result = X402::Settlements::SettleService.call(verified_payment:, kind: :invoice_payment, invoice:)
        return answer_failure(settle_result.error, verified_payment.payment_digest) if settle_result.failure?

        if settle_result.outcome == :settled
          finish(settle_result.settlement, settle_result.transaction_hash)
        else
          answer(settle_result.settlement)
        end
      end

      def finish(settlement, transaction_hash)
        finished = X402::Invoices::FinishPaymentService.call(settlement:, transaction_hash:)
        answer(finished.settlement)
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("#{self.class.name} call failed reason=finish_failed network=#{settlement.network} error=#{e.class.name}")
        answer(settlement.reload)
      end

      def answer_failure(error, digest)
        codes = error.is_a?(BaseService::ValidationFailure) ? error.messages.values.flatten : []
        own = invoice.x402_settlements.where(status: %i[pending settled]).find_by(payment_digest: digest) if codes.intersect?(RACE_CODES)

        if own
          answer_replay(own)
        elsif codes.include?("x402_connection_changed")
          result.not_found_failure!(resource: "invoice")
        else
          result.fail_with_error!(error)
        end
      end

      def answer_replay(settlement)
        Rails.logger.info("#{self.class.name} replay status=#{settlement.status} network=#{settlement.network}")
        answer(settlement)
      end

      def answer(settlement)
        result.settlement = settlement
        result
      end

      def refuse(field, code)
        result.single_validation_failure!(error_code: code, field:)
      end
    end
  end
end
