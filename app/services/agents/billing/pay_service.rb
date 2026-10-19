# frozen_string_literal: true

module Agents
  module Billing
    class PayService < BaseService
      Result = BaseResult[:wallet_transaction, :replayed]

      PAYMENT_METHODS = ["shared_payment_token"].freeze

      def initialize(storefront:, registration:, params:)
        @storefront = storefront
        @registration = registration
        @params = params

        super
      end

      def call
        return result.validation_failure!(errors: input_errors) if input_errors.any?
        return result.single_validation_failure!(error_code: "enrollment_required") unless wallet

        result.wallet_transaction = paid_with_token
        if result.wallet_transaction
          result.replayed = true
          return result
        end

        attach_stripe_customer

        topup = WalletTransactions::CreateFromParamsService.call(
          organization: storefront.organization,
          params: {
            wallet_id: wallet.id,
            paid_credits: credits.to_s("F"),
            invoice_requires_successful_payment: true,
            payment_method: {payment_method_type: "provider", shared_payment_token: params[:shared_payment_token]}
          }
        )
        return result.fail_with_error!(topup.error) unless topup.success?

        result.wallet_transaction = topup.wallet_transactions.first
        result.replayed = false
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :storefront, :registration, :params

      def input_errors
        @input_errors ||= {
          amount_cents: (["value_is_invalid"] unless amount_cents&.positive?),
          shared_payment_token: (["value_is_mandatory"] if params[:shared_payment_token].blank?)
        }.compact
      end

      def amount_cents
        @amount_cents ||= Integer(params[:amount_cents].to_s, 10, exception: false)
      end

      def wallet
        @wallet ||= registration.wallet
      end

      def customer
        wallet.customer
      end

      def credits
        BigDecimal(amount_cents) / Money::Currency.new(wallet.currency).subunit_to_unit / wallet.rate_amount
      end

      def paid_with_token
        wallet.wallet_transactions.joins(:payment_method).find_by(payment_methods: {provider_method_id: params[:shared_payment_token]})
      end

      # The token is charged on the storefront's Stripe account, through a Stripe customer that only pays with tokens.
      def attach_stripe_customer
        registration.with_lock do
          next if customer.reload.stripe_customer&.provider_customer_id.present?

          customer.update!(payment_provider: "stripe", payment_provider_code: storefront.payment_provider_code)
          PaymentProviders::Stripe::Customers::CreateService.call!(
            customer:,
            payment_provider_id: storefront.stripe_provider.id,
            params: {sync_with_provider: true, provider_payment_methods: PAYMENT_METHODS},
            async: false,
            allow_shared_payment_token: true
          )
        end
      end
    end
  end
end
