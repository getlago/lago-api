# frozen_string_literal: true

module X402
  module CreditPurchases
    class ValidateService < BaseService
      Result = BaseResult

      def initialize(connection:, params:, verified_payment: nil)
        @connection = connection
        @params = params
        @verified_payment = verified_payment

        super
      end

      def call
        return result.validation_failure!(errors: input_errors) if input_errors.any?
        return result.not_found_failure!(resource: "plan") unless plan_exists?
        return result unless verified_payment

        return refuse("buyer_not_recognized") if customer.nil? && !connection.auto_create_customers
        return refuse("buyer_external_id_taken") if customer.nil? && external_id_taken?
        return refuse("wallet_not_x402_enabled") if wallet && !wallet.x402_enabled
        return refuse("subscription_not_active") if active_subscription.nil? && subscriptions.any?

        if above_maximum?
          refuse("amount_above_maximum", field: :payment_requirements)
        else
          result
        end
      end

      private

      attr_reader :connection, :params, :verified_payment

      delegate :organization, to: :connection, private: true
      delegate :payer_address, :family, to: :verified_payment, private: true

      def input_errors
        @input_errors ||= {
          plan_code: mandatory(:plan_code),
          wallet_code: mandatory(:wallet_code)
        }.compact
      end

      def mandatory(field)
        ["value_is_mandatory"] if params[field].blank?
      end

      def plan_exists?
        organization.plans.parents.exists?(code: params[:plan_code])
      end

      def customer
        if defined?(@customer)
          @customer
        else
          @customer = organization.customers.by_x402_agent_address(payer_address).first
        end
      end

      def external_id_taken?
        organization.customers.exists?(external_id: X402::ExternalIds.customer(payer_address, family:))
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
          external_id = X402::ExternalIds.subscription(payer_address, params[:plan_code], family:)
          customer.subscriptions.where(external_id:, status: %i[active pending incomplete]).to_a
        else
          []
        end
      end

      def active_subscription
        subscriptions.find(&:active?)
      end

      def above_maximum?
        max = wallet&.paid_top_up_max_amount_cents
        max.present? && verified_payment.settled_amount_cents > max
      end

      def refuse(code, field: :base)
        result.single_validation_failure!(error_code: code, field:)
      end
    end
  end
end
