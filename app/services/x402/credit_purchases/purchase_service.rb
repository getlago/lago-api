# frozen_string_literal: true

module X402
  module CreditPurchases
    # E8 (D4, §5.2): verify → pending row (1a) → settle → flip → grant (1b). Lago settles; the middleware only
    # forwards the agent's payment, and nothing about the transfer is taken from the request (D15).
    # POC: no replay answer, no per-payer pending index, no reconciliation of a pending row (T10).
    class PurchaseService < BaseService
      RECONCILE_MARGIN = 30.seconds

      Result = BaseResult[:settlement]

      def initialize(organization:, params:)
        @organization = organization
        @params = params
        super
      end

      def call
        return result.not_found_failure!(resource: "x402_connection") unless connection
        return result.not_found_failure!(resource: "plan") unless organization.plans.parents.exists?(code: params[:plan_code])

        unless requirements_match_connection?
          return result.single_validation_failure!(field: :payment_requirements, error_code: "does_not_match_connection")
        end

        verification = facilitator.verify(payment:, payment_requirements:)
        return result.single_validation_failure!(field: :payment, error_code: verification.invalid_reason) unless verification.valid

        settlement = create_pending_settlement(verification)
        settle(settlement)
        return result.single_validation_failure!(field: :payment, error_code: settlement.error_reason) if settlement.failed?

        GrantService.call!(settlement:) if settlement.settled?

        result.settlement = settlement
        result
      end

      private

      attr_reader :organization, :params

      def connection
        @connection ||= organization.x402_connections.find_by(code: params[:connection_code])
      end

      def facilitator
        @facilitator ||= X402::Facilitator::CoinbaseCdpAdapter.new(connection:)
      end

      def payment
        params[:payment]
      end

      def payment_requirements
        params[:payment_requirements]
      end

      def authorization
        payment.dig("payload", "authorization")
      end

      def network
        payment_requirements["network"]
      end

      def asset
        @asset ||= X402::Asset.fetch(code: connection.asset, network:)
      end

      # §8.3: the requirements are the caller's, so they are compared with the connection, never trusted.
      def requirements_match_connection?
        connection.networks.include?(network) &&
          payment_requirements["scheme"] == "exact" &&
          same_address?(payment_requirements["asset"], asset.address) &&
          same_address?(payment_requirements["payTo"], connection.payout_address_for(network)) &&
          same_address?(authorization["to"], connection.payout_address_for(network))
      end

      def same_address?(left, right)
        X402::Network.checksum(left) == X402::Network.checksum(right)
      end

      # D4 phase 1a: written alone, before /settle, from the payment the facilitator verified (D15).
      def create_pending_settlement(verification)
        amount_atomic = Integer(authorization.fetch("value"))

        organization.x402_settlements.create!(
          x402_connection: connection,
          kind: :credit_purchase,
          status: :pending,
          network:,
          asset: asset.address,
          payer_address: X402::Network.checksum(authorization.fetch("from")),
          payee_address: X402::Network.checksum(authorization.fetch("to")),
          settled_amount_atomic: amount_atomic,
          settled_amount_cents: amount_atomic / asset.atomic_units_per_cent, # D11: the first floor
          payment_digest: X402::PaymentDigest.evm(network:, asset: asset.address, authorization:),
          purchase_settings: {"plan_code" => params[:plan_code], "wallet_code" => params[:wallet_code], "wallet" => params[:wallet].to_h},
          payload: {"payment" => payment, "payment_requirements" => payment_requirements, "verify_response" => verification.response},
          reconcile_after:
        )
      end

      # §6.2: when a negative chain read becomes final — capped by Lago's own window.
      def reconcile_after
        valid_before = Time.zone.at(Integer(authorization.fetch("validBefore")))
        window = Integer(payment_requirements.fetch("maxTimeoutSeconds", PaymentRequirementsService::MAX_TIMEOUT_SECONDS))

        [valid_before, window.seconds.from_now].min + RECONCILE_MARGIN
      end

      def settle(settlement)
        settle_result = facilitator.settle(payment:, payment_requirements:)
        payload = settlement.payload.merge("settle_response" => settle_result.response)

        case settle_result.status
        when :settled
          settlement.update!(status: :settled, transaction_hash: settle_result.transaction, payload:)
        when :failed
          settlement.update!(status: :failed, error_reason: settle_result.error_reason.presence || "settle_failed", payload:)
        else
          # Unconfirmed (§5.1): stays pending with any hash CDP returned; reconciliation (T10) is out of POC scope.
          settlement.update!(transaction_hash: settle_result.transaction, payload:)
        end
      end
    end
  end
end
