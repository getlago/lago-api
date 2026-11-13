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

        # Before the other checks: an agent that lost the answer learns whether it paid, even once the merchant
        # stopped accepting payments.
        paid = paid_with_token
        return replay(paid) if paid

        return result.single_validation_failure!(error_code: "payments_not_accepted") if storefront.stripe_provider&.seller_profile.blank?

        # Checked before anything is written: a refused request pins neither a Stripe customer nor the connection.
        limits = Validators::WalletTransactionAmountLimitsValidator.new(result, wallet:, credits_amount: credits.to_s("F"), field_name: :amount_cents)
        return result unless limits.valid?

        # Committed on its own: Stripe keeps the customer whatever the top-up below answers.
        attach_stripe_customer

        # One lock for the replay check and the top-up, so the same token sent twice at once pays once.
        registration.with_lock do
          paid = paid_with_token
          paid ? replay(paid) : create_topup
        end

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :storefront, :registration, :params

      def input_errors
        @input_errors ||= {
          amount_cents: (["value_is_invalid"] unless amount_cents&.positive?),
          shared_payment_token: token_error
        }.compact
      end

      def token_error
        return ["value_is_mandatory"] if shared_payment_token.blank?

        ["value_is_invalid"] unless PaymentMethod::SHARED_PAYMENT_TOKEN_FORMAT.match?(shared_payment_token)
      end

      def amount_cents
        @amount_cents ||= Integer(params[:amount_cents].to_s, 10, exception: false)
      end

      # As a string: a JSON number is a malformed token, not an exception.
      def shared_payment_token
        @shared_payment_token ||= params[:shared_payment_token].to_s
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
        wallet.wallet_transactions.joins(:payment_method).find_by(payment_methods: {provider_method_id: shared_payment_token})
      end

      # A token pays one top-up: the same token with another amount is refused, as Stripe refuses an idempotency key
      # reused with other parameters.
      def replay(paid)
        if paid.credit_amount != credits
          return result.single_validation_failure!(field: :shared_payment_token, error_code: "value_already_exist")
        end

        result.wallet_transaction = paid
        result.replayed = true
        result
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

      def create_topup
        topup = WalletTransactions::CreateFromParamsService.call(
          organization: storefront.organization,
          params: {
            wallet_id: wallet.id,
            paid_credits: credits.to_s("F"),
            invoice_requires_successful_payment: true,
            payment_method: {payment_method_type: "provider", shared_payment_token:}
          }
        )
        # The agent sent shared_payment_token, not a payment method.
        if topup.error.is_a?(BaseService::ValidationFailure)
          errors = topup.error.messages.transform_keys { (it == :payment_method) ? :shared_payment_token : it }
          result.validation_failure!(errors:).raise_if_error!
        end
        topup.raise_if_error!

        result.wallet_transaction = topup.wallet_transactions.first
        result.replayed = false
      end
    end
  end
end
