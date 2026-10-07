# frozen_string_literal: true

module X402
  module GateChecks
    class CheckService < BaseService
      DEGRADED_CALL_HEADROOM = 1_000
      MAX_AGENT_ADDRESS_LENGTH = 44
      MAX_ESTIMATED_CALL_COST_CENTS = 2**63 - 1

      Result = BaseResult[:balance_credits, :requirements, :external_subscription_id]

      def initialize(organization:, params:)
        @organization = organization
        @params = params

        super
      end

      def call
        return result.validation_failure!(errors: input_errors) if input_errors.any?
        return result.not_found_failure!(resource: "connection") unless connection

        route = RouteCheckService.call(organization:, plan_code: params[:plan_code], billable_metric_code: params[:billable_metric_code])
        return result.fail_with_error!(route.error) unless route.success?

        return refuse("buyer_not_recognized") if customer.nil? && !connection.auto_create_customers
        return refuse("wallet_not_x402_enabled") if wallet && !wallet.x402_enabled
        return refuse("customer_not_refreshable") if customer && customer.error_details.tax_error.exists?
        return refuse("subscription_not_active") if active_subscription.nil? && subscriptions.any?

        result.external_subscription_id = active_subscription&.external_id
        result.balance_credits = balance_credits

        if active_subscription && wallet && covered?
          result
        else
          challenge
        end
      end

      private

      attr_reader :organization, :params

      def challenge
        return result.validation_failure!(errors: {amount_cents: ["amount_above_maximum"]}) if above_maximum?
        return refuse("credit_purchase_pending") if credit_purchase_pending?
        return refuse("agent_address_family_unsupported") if agent_address && connection_families.exclude?(agent_family)

        requirements = X402::PaymentRequirementsService.call(connection:, amount_cents:)

        if requirements.success?
          result.requirements = requirements.requirements
          result
        else
          result.fail_with_error!(requirements.error)
        end
      end

      def input_errors
        @input_errors ||= {
          plan_code: mandatory(:plan_code),
          billable_metric_code: mandatory(:billable_metric_code),
          wallet_code: mandatory(:wallet_code),
          amount_cents: positive_integer(:amount_cents),
          estimated_call_cost_cents: positive_integer(:estimated_call_cost_cents, max: MAX_ESTIMATED_CALL_COST_CENTS),
          agent_address: (["invalid_format"] if agent_address && !valid_agent_address?)
        }.compact
      end

      def mandatory(field)
        ["value_is_mandatory"] if params[field].blank?
      end

      def positive_integer(field, max: nil)
        value = X402::UnsignedInteger.parse(params[field])

        if params[field].nil?
          ["value_is_mandatory"]
        elsif !value&.positive? || (max && value > max)
          ["invalid_value"]
        end
      end

      def valid_agent_address?
        agent_family.present? && X402::Network.valid_address?(agent_address, family: agent_family)
      end

      def agent_address
        params[:agent_address]&.to_s
      end

      def agent_family
        if defined?(@agent_family)
          @agent_family
        else
          @agent_family = decodable_agent_address? ? X402::Network.family_of_address(agent_address) : nil
        end
      end

      def decodable_agent_address?
        agent_address.present? && agent_address.length <= MAX_AGENT_ADDRESS_LENGTH
      end

      def amount_cents
        X402::UnsignedInteger.parse(params[:amount_cents])
      end

      def estimated_call_cost_cents
        X402::UnsignedInteger.parse(params[:estimated_call_cost_cents])
      end

      def connection
        @connection ||= organization.x402_connections.find_by(code: params[:connection_code])
      end

      def customer
        if defined?(@customer)
          @customer
        else
          @customer = agent_address && organization.customers.by_x402_agent_address(agent_address).first
        end
      end

      def wallet
        if defined?(@wallet)
          @wallet
        else
          @wallet = customer && customer.wallets.active.find_by(code: params[:wallet_code])
        end
      end

      def subscriptions
        @subscriptions ||= if customer
          external_id = X402::ExternalIds.subscription(agent_address, params[:plan_code], family: agent_family)
          customer.subscriptions.where(external_id:, status: %i[active pending incomplete]).to_a
        else
          []
        end
      end

      def active_subscription
        subscriptions.find(&:active?)
      end

      def covered?
        reserved = reserve

        if reserved.nil?
          computed_base >= DEGRADED_CALL_HEADROOM * estimated_call_cost_cents
        elsif computed_base - reserved >= estimated_call_cost_cents
          true
        else
          reservation_counter.release(estimated_call_cost_cents)
          false
        end
      end

      def reserve
        if X402::ReservationCounter.enabled?(organization)
          reservation_counter.reserve(estimated_call_cost_cents)
        end
      end

      def reservation_counter
        @reservation_counter ||= X402::ReservationCounter.new(wallet)
      end

      def computed_base
        wallet.balance_cents - wallet.ongoing_usage_balance_cents
      end

      def balance_credits
        if wallet
          wallet.credits_balance - wallet.credits_ongoing_usage_balance
        else
          BigDecimal(0)
        end
      end

      def above_maximum?
        max = wallet&.paid_top_up_max_amount_cents
        max.present? && amount_cents > max
      end

      def credit_purchase_pending?
        agent_address.present? &&
          organization.x402_settlements.credit_purchase.pending
            .exists?(payer_address: X402::Network.normalize_address(agent_address, family: agent_family))
      end

      def connection_families
        connection.networks.map { |network| X402::Network.family_of_network(network) }
      end

      def refuse(code)
        result.single_validation_failure!(error_code: code)
      end
    end
  end
end
