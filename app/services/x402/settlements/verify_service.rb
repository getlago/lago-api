# frozen_string_literal: true

module X402
  module Settlements
    class VerifyService < BaseService
      Result = BaseResult[:verified_payment]
      CLOCK_SKEW_TOLERANCE = 30.seconds

      def initialize(connection:, payment:, payment_requirements:, settle_response: nil, verify_response: nil)
        @connection = connection
        @payment = payment
        @payment_requirements = payment_requirements
        @settle_response = settle_response
        @verify_response = verify_response

        super
      end

      def call
        return refuse(:payment, "invalid_payment") unless serialisable?(payment)
        return refuse(:payment_requirements, "invalid_payment_requirements") unless serialisable?(payment_requirements)

        response_failure = responses_failure
        return refuse(*response_failure) if response_failure

        term_failure = terms_failure
        return refuse(*term_failure) if term_failure

        digest_result = X402::Payments::ComputeDigestService.call(payment:, network: payment_payload.network, asset: payment_payload.asset)
        return result.validation_failure!(errors: digest_result.error.messages) if digest_result.failure?

        family_failure = (family == :evm) ? evm_failure : svm_failure
        return refuse(*family_failure) if family_failure

        if recorded?
          check_settle_response(digest_result.digest)
        else
          verify_with_facilitator(digest_result.digest)
        end
      end

      private

      attr_reader :connection, :payment, :payment_requirements, :settle_response, :verify_response

      def recorded?
        !settle_response.nil?
      end

      def verify_with_facilitator(digest)
        verification = X402::Facilitator::Client.for(connection).verify(payment:, payment_requirements:)
        return refuse(:payment, verification.invalid_reason) unless verification.valid

        reported = reported_payer(verification)
        anomaly = payer_anomaly(reported)
        raise_anomaly(anomaly, verification) if anomaly

        answer(digest, verification.response)
      end

      def check_settle_response(digest)
        failure = settle_response_failure

        if failure
          refuse(*failure)
        else
          answer(digest, verify_response&.deep_stringify_keys)
        end
      end

      def answer(digest, verify_answer)
        result.verified_payment = X402::Settlements::VerifiedPayment.new(
          connection:,
          payment_payload:,
          payer_address: derived_payer,
          payment_digest: digest,
          verify_response: verify_answer
        )
        result
      end

      def payment_payload
        @payment_payload ||= X402::PaymentPayload.new(payment:, payment_requirements:)
      end

      def family
        payment_payload.family
      end

      def serialisable?(value)
        return false unless value.is_a?(Hash)

        value.to_json
        !nul_in?(value)
      rescue JSON::GeneratorError
        false
      end

      def nul_in?(value)
        case value
        when Hash
          value.any? { |key, nested| nul_in?(key.to_s) || nul_in?(nested) }
        when Array
          value.any? { |nested| nul_in?(nested) }
        when String
          value.include?("\u0000")
        else
          false
        end
      end

      def refuse(field, code)
        result.validation_failure!(errors: {field => [code]})
      end

      def responses_failure
        return unless recorded?

        if !serialisable?(settle_response)
          [:settle_response, "invalid_settle_response"]
        elsif !verify_response.nil? && !serialisable?(verify_response)
          [:verify_response, "invalid_verify_response"]
        end
      end

      def terms_failure
        network = payment_payload.network
        asset = X402::Asset::DEFINITIONS[[connection.asset, network]]&.address
        amount = payment_payload.amount
        timeout = payment_payload.max_timeout_seconds

        if payment_payload.x402_version != X402::PaymentPayload::X402_VERSION
          [:payment, "unsupported_x402_version"]
        elsif payment_payload.scheme != X402::PaymentPayload::SCHEME
          [:payment_requirements, "unsupported_scheme"]
        elsif connection.networks.exclude?(network)
          [:payment_requirements, "unsupported_network"]
        elsif X402::Network.normalize_address(payment_payload.asset, family:) != asset
          [:payment_requirements, "unsupported_asset"]
        elsif X402::Network.normalize_address(payment_payload.pay_to, family:) != connection.payout_addresses[family.to_s]
          [:payment_requirements, "invalid_pay_to"]
        elsif amount.nil? || amount < X402::Asset.fetch(code: connection.asset, network:).atomic_units_per_cent
          [:payment_requirements, "invalid_amount"]
        elsif !recorded? && (timeout.nil? || !(1..X402::PaymentPayload::MAX_TIMEOUT_SECONDS).cover?(timeout))
          [:payment_requirements, "invalid_max_timeout_seconds"]
        end
      end

      def evm_failure
        if !X402::Network.valid_address?(payment_payload.from, family: :evm)
          [:payment, "invalid_authorization"]
        elsif X402::Network.normalize_address(payment_payload.to, family: :evm) != connection.payout_addresses["evm"]
          [:payment, "invalid_pay_to"]
        elsif !recorded? && payment_payload.valid_before > Time.current.to_i + payment_payload.max_timeout_seconds + CLOCK_SKEW_TOLERANCE.to_i
          [:payment, "invalid_valid_before"]
        end
      end

      def svm_failure
        svm_payer
        nil
      rescue X402::Chain::UnreadablePaymentError
        [:payment, "unsupported_transaction"]
      end

      def svm_reader
        @svm_reader ||= X402::Chain::SvmReader.new(network: payment_payload.network, payment:, payment_requirements:, since: Time.current)
      end

      def svm_payer
        @svm_payer ||= svm_reader.payer
      end

      def settle_response_failure
        if settled["success"] != true || !X402::Network.valid_transaction?(settled["transaction"], family:)
          [:settle_response, "settle_not_successful"]
        elsif transferred_amount != payment_payload.amount
          [:payment, "amount_mismatch"]
        elsif family == :svm && svm_reader.mint != payment_payload.asset
          [:payment, "asset_mismatch"]
        elsif settled["network"] != payment_payload.network
          settle_mismatch("network_mismatch")
        elsif !settled_payer_matches?
          settle_mismatch("payer_mismatch")
        end
      rescue X402::Chain::UnreadablePaymentError
        [:payment, "unsupported_transaction"]
      end

      def settled
        @settled ||= settle_response.deep_stringify_keys
      end

      def transferred_amount
        (family == :evm) ? payment_payload.value : svm_reader.transfer_amount
      end

      def settled_payer_matches?
        payer = settled["payer"]
        payer.nil? || X402::Network.normalize_address(payer, family:) == derived_payer
      end

      def settle_mismatch(reason)
        Rails.logger.warn("#{self.class.name} call failed reason=#{reason} network=#{payment_payload.network}")
        [:settle_response, "does_not_match_payment"]
      end

      def derived_payer
        (family == :evm) ? X402::Network.normalize_address(payment_payload.from, family: :evm) : svm_payer
      end

      def reported_payer(verification)
        reported = verification.payer.presence
        reported && X402::Network.normalize_address(reported, family:)
      end

      def payer_anomaly(reported)
        if reported.nil? && family == :svm
          "payer_missing"
        elsif reported.present? && reported != derived_payer
          "payer_mismatch"
        end
      end

      def raise_anomaly(reason, verification)
        Rails.logger.warn("#{self.class.name} call failed reason=#{reason} network=#{payment_payload.network}")

        raise X402::Facilitator::UnavailableError.new("verify: #{reason}", error_type: reason, correlation_id: verification.response["correlationId"])
      end
    end
  end
end
