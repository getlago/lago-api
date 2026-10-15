# frozen_string_literal: true

module X402
  module Settlements
    class VerifiedPayment < Data.define(:connection, :payment_payload, :payer_address, :payment_digest, :verify_response)
      delegate :payment, :payment_requirements, :network, :family, :asset, to: :payment_payload

      def payee_address
        (family == :evm) ? payment_payload.to : payment_payload.pay_to
      end

      def settled_amount_atomic
        (family == :evm) ? payment_payload.value : payment_payload.amount
      end

      def settled_amount_cents
        X402::Asset.fetch(code: connection.asset, network:).cents_from_atomic(settled_amount_atomic)
      end
    end
  end
end
