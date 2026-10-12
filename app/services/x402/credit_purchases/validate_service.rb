# frozen_string_literal: true

module X402
  module CreditPurchases
    class ValidateService < BaseService
      Result = BaseResult

      WALLET_CURRENCY = "USD"
      LIMIT_KEYS = %i[paid_top_up_min_amount_cents paid_top_up_max_amount_cents].freeze
      MAX_LIMIT_CENTS = 2**63 - 1
      MAX_RATE_AMOUNT = BigDecimal("9999999999999999999999999.99999")

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
        return refuse("amount_above_maximum", field: :payment_requirements) if above_maximum?

        if wallet.nil? && shape_errors.any?
          result.validation_failure!(errors: {wallet: shape_errors})
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

      def shape
        params[:wallet]
      end

      def shape_errors
        @shape_errors ||= if shape.is_a?(Hash)
          [
            ("currency_not_supported" if shape[:currency] != WALLET_CURRENCY),
            ("invalid_rate_amount" unless valid_rate_amount?),
            ("invalid_paid_top_up_limits" unless valid_limits?)
          ].compact
        else
          ["value_is_mandatory"]
        end
      end

      def valid_rate_amount?
        rated = Wallet.new(rate_amount: shape[:rate_amount]).tap(&:validate)
        rated.errors[:rate_amount].empty? && rated.rate_amount <= MAX_RATE_AMOUNT
      end

      def valid_limits?
        limits = shape.slice(*LIMIT_KEYS).compact.transform_values { |value| X402::UnsignedInteger.parse(value) }
        return false unless limits.values.all? { |cents| cents&.positive? && cents <= MAX_LIMIT_CENTS }

        min, max = limits.values_at(*LIMIT_KEYS)
        min.nil? || max.nil? || max >= min
      end

      def refuse(code, field: :base)
        result.single_validation_failure!(error_code: code, field:)
      end
    end
  end
end
