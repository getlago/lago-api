# frozen_string_literal: true

module X402
  module GateChecks
    # E7 (§2.3, §2.7): "does this agent have balance?" Creates nothing; the agent address is a claim here (D15).
    # POC: no reservation counter (§4.4) and, of the route checks, only plan_not_found.
    class CheckService < BaseService
      Result = BaseResult[:balance_credits, :requirements, :external_subscription_id]

      def initialize(organization:, params:)
        @organization = organization
        @params = params
        super
      end

      def call
        connection = organization.x402_connections.find_by(code: params[:connection_code])
        return result.not_found_failure!(resource: "x402_connection") unless connection

        plan = organization.plans.parents.find_by(code: params[:plan_code])
        return result.not_found_failure!(resource: "plan") unless plan

        agent_address = X402::Network.checksum(params[:agent_address]) if params[:agent_address].present?
        customer = organization.customers.find_by(x402_agent_address: agent_address) if agent_address
        subscription_id = X402::ExternalIds.subscription(agent_address, plan.code) if agent_address
        subscription = customer&.subscriptions&.active&.find_by(external_id: subscription_id)
        wallet = customer&.wallets&.active&.find_by(code: params[:wallet_code])

        result.external_subscription_id = subscription&.external_id
        result.balance_credits = wallet ? wallet.credits_balance - wallet.credits_ongoing_usage_balance : BigDecimal("0")
        result.requirements = funded?(subscription, wallet) ? nil : challenge(connection)
        result
      end

      private

      attr_reader :organization, :params

      # D6: the base is computed from the wallet row, so an E8 grant counts the moment it commits.
      def funded?(subscription, wallet)
        subscription.present? && wallet.present? &&
          wallet.balance_cents - wallet.ongoing_usage_balance_cents >= params[:estimated_call_cost_cents].to_i
      end

      def challenge(connection)
        PaymentRequirementsService.call!(connection:, amount_cents: params[:amount_cents].to_i).requirements
      end
    end
  end
end
