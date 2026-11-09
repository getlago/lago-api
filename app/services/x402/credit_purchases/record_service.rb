# frozen_string_literal: true

module X402
  module CreditPurchases
    class RecordService < BaseService
      Result = BaseResult[:settlement]

      UNIQUE_INDEX_FAILURES = {
        "index_x402_settlements_on_payment_digest" => [:base, "payment_already_recorded"],
        "index_x402_settlements_on_network_and_transaction_hash" => [:settle_response, "transaction_already_recorded"]
      }.freeze

      def initialize(verified_payment:, settle_response:, purchase_settings:, request_key_digest:)
        @verified_payment = verified_payment
        @settle_response = settle_response
        @purchase_settings = purchase_settings
        @request_key_digest = request_key_digest

        super
      end

      def call
        result.settlement = X402::Settlement.create!(
          organization_id: connection.organization_id,
          x402_connection: connection,
          kind: :credit_purchase,
          status: :settled,
          settled_by: :merchant,
          transaction_hash: settled["transaction"],
          purchase_settings:,
          network: verified_payment.network,
          asset: verified_payment.asset,
          payer_address: verified_payment.payer_address,
          payee_address: verified_payment.payee_address,
          settled_amount_atomic: verified_payment.settled_amount_atomic,
          settled_amount_cents: verified_payment.settled_amount_cents,
          payment_digest: verified_payment.payment_digest,
          request_key_digest:,
          payload: {
            "payment" => verified_payment.payment,
            "payment_requirements" => verified_payment.payment_requirements,
            "verify_response" => verified_payment.verify_response,
            "settle_response" => settled
          }.compact
        )
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique => e
        field, code = UNIQUE_INDEX_FAILURES[violated_unique_index(e)]
        raise unless code

        result.single_validation_failure!(field:, error_code: code)
      end

      private

      attr_reader :verified_payment, :settle_response, :purchase_settings, :request_key_digest

      delegate :connection, to: :verified_payment, private: true

      def settled
        @settled ||= settle_response.deep_stringify_keys
      end
    end
  end
end
