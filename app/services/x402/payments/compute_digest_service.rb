# frozen_string_literal: true

module X402
  module Payments
    class ComputeDigestService < BaseService
      Result = BaseResult[:digest]

      AUTHORIZATION_FIELDS = %w[from to value validAfter validBefore nonce].freeze
      NONCE = /\A0x\h{64}\z/

      def initialize(payment:, network:, asset: nil)
        @payment = payment
        @network = network
        @asset = asset

        super
      end

      def call
        return invalid("invalid_payment") unless payment.is_a?(Hash)
        return invalid("unsupported_network") unless supported_network?

        canonical = (Network.family_of_network(network) == :evm) ? evm_canonical : svm_canonical
        return result if result.failure?

        result.digest = OpenSSL::Digest::SHA256.hexdigest(JSON.generate(canonical))
        result
      end

      private

      attr_reader :payment, :network, :asset

      def supported_network?
        Network.family_of_network(network)
        true
      rescue ArgumentError
        false
      end

      def evm_canonical
        return invalid("invalid_asset") unless Network::EVM_ADDRESS.match?(asset.to_s)

        authorization = payload["authorization"]
        return invalid("invalid_authorization") unless valid_authorization?(authorization)

        [
          "evm",
          network,
          Network.checksum(asset),
          Network.checksum(authorization["from"]),
          Network.checksum(authorization["to"]),
          UnsignedInteger.parse(authorization["value"]),
          UnsignedInteger.parse(authorization["validAfter"]),
          UnsignedInteger.parse(authorization["validBefore"]),
          authorization["nonce"].downcase
        ]
      end

      def svm_canonical
        transaction = payload["transaction"]
        return invalid("invalid_transaction") unless transaction.is_a?(String) && transaction.present?

        Base64.strict_decode64(transaction)
        ["svm", network, transaction]
      rescue ArgumentError
        invalid("invalid_transaction")
      end

      def payload
        stringified = payment.deep_stringify_keys["payload"]
        stringified.is_a?(Hash) ? stringified : {}
      end

      def valid_authorization?(authorization)
        return false unless authorization.is_a?(Hash) && AUTHORIZATION_FIELDS.all? { |field| authorization.key?(field) }
        return false unless [authorization["from"], authorization["to"]].all? { |address| Network::EVM_ADDRESS.match?(address.to_s) }
        return false unless NONCE.match?(authorization["nonce"].to_s)

        %w[value validAfter validBefore].all? { |field| UnsignedInteger.parse(authorization[field]) }
      end

      def invalid(code)
        result.validation_failure!(errors: {payment: [code]})
      end
    end
  end
end
