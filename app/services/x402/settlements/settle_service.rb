# frozen_string_literal: true

module X402
  module Settlements
    class SettleService < BaseService
      Result = BaseResult[:settlement, :outcome, :transaction_hash]
      RECONCILE_MARGIN = 30.seconds
      SVM_SIGNATURE_BYTES = 64
      RACE_CODES = {
        "index_x402_settlements_on_payment_digest" => "payment_already_recorded",
        "index_x402_settlements_on_pending_credit_purchase_payer" => "credit_purchase_pending",
        "index_x402_settlements_on_pending_invoice_id" => "invoice_payment_pending"
      }.freeze

      def initialize(verified_payment:, kind:, invoice: nil, purchase_settings: nil)
        @verified_payment = verified_payment
        @kind = kind
        @invoice = invoice
        @purchase_settings = purchase_settings

        super
      end

      def call
        raise "#{self.class.name} must run outside a database transaction" if in_transaction?

        settlement = insert_pending
        return result if result.failure?

        result.settlement = settlement
        settle(settlement)
        result
      end

      private

      attr_reader :verified_payment, :kind, :invoice, :purchase_settings

      delegate :connection, :network, :asset, to: :verified_payment, private: true

      def insert_pending
        X402::Settlement.create!(
          organization_id: connection.organization_id,
          x402_connection: connection,
          kind:,
          status: :pending,
          invoice:,
          purchase_settings:,
          network:,
          asset:,
          payer_address: verified_payment.payer_address,
          payee_address: verified_payment.payee_address,
          settled_amount_atomic: verified_payment.settled_amount_atomic,
          settled_amount_cents: verified_payment.settled_amount_cents,
          payment_digest: verified_payment.payment_digest,
          reconcile_after:,
          payload: {
            "payment" => verified_payment.payment,
            "payment_requirements" => verified_payment.payment_requirements,
            "verify_response" => verified_payment.verify_response
          }
        )
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        code = RACE_CODES.find { |index, _| e.message.include?(index) }&.last

        if code
          result.single_validation_failure!(error_code: code)
        else
          raise
        end
      end

      def reconcile_after
        if verified_payment.family == :evm
          Time.zone.at(verified_payment.payment_payload.valid_before) + RECONCILE_MARGIN
        else
          Time.current + X402::Chain::SvmReader::EXPIRY_PROOF
        end
      end

      def settle(settlement)
        settle_result = X402::Facilitator::Client.for(connection).settle(
          payment: verified_payment.payment,
          payment_requirements: verified_payment.payment_requirements
        )
        settled_hash = settled_transaction(settle_result)
        malformed = settle_result.settled? && settled_hash.nil?
        log_failure("malformed_transaction") if malformed

        record(
          settlement,
          payload: settlement.payload.merge("settle_response" => settle_result.response),
          error_reason: malformed ? "malformed_response" : settle_result.error_reason,
          transaction_hash: pending_hash(settle_result)
        )

        result.outcome = settled_hash ? :settled : :pending
        result.transaction_hash = settled_hash
      rescue X402::Facilitator::CredentialError => e
        record_unsettled(settlement, "credential_error", e)
      rescue X402::Facilitator::RateLimitError => e
        record_unsettled(settlement, "rate_limited", e)
      end

      def settled_transaction(settle_result)
        if settle_result.settled? && well_formed_hash?(settle_result.transaction)
          settle_result.transaction
        end
      end

      def pending_hash(settle_result)
        transaction = settle_result.transaction

        if settle_result.outcome == :settlement_pending && well_formed_hash?(transaction)
          transaction
        end
      end

      def well_formed_hash?(transaction)
        return false unless transaction.is_a?(String)

        if verified_payment.family == :evm
          X402::Chain::EvmReader::HEX_WORD.match?(transaction)
        else
          X402::Base58.decode(transaction)&.bytesize == SVM_SIGNATURE_BYTES
        end
      end

      def record_unsettled(settlement, error_reason, error)
        settle_response = {"httpStatus" => error.http_status, "errorType" => error.error_type, "correlationId" => error.correlation_id}.compact

        record(settlement, payload: settlement.payload.merge("settle_response" => settle_response), error_reason:)
        result.outcome = :pending
      end

      def record(settlement, **attributes)
        settlement.update!(**attributes)
      rescue ActiveRecord::ActiveRecordError, ArgumentError => e
        settlement.restore_attributes
        log_failure("record_failed", error: e.class.name)
      end

      def log_failure(reason, **details)
        context = {reason:, **details, network:}.map { |key, value| "#{key}=#{value}" }.join(" ")

        Rails.logger.warn("#{self.class.name} call failed #{context}")
      end
    end
  end
end
