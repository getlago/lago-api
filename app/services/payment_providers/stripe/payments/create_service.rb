# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class CreateService < BaseService
        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          stripe_result = create_payment_intent

          payment.provider_payment_id = stripe_result.id
          payment.status = stripe_result.status
          payment.payable_payment_status = payment.payment_provider&.determine_payment_status(payment.status)
          payment.provider_payment_data = stripe_result.next_action if stripe_result.status == "requires_action"
          payment.save!

          handle_requires_action(payment) if payment.status == "requires_action"

          result.payment = payment
          result

        # TODO: global refactor of the error handling
        # identified processing errors should mark it as failed to allow reprocess via a new payment
        # other should be reprocessed
        rescue ::Stripe::AuthenticationError, ::Stripe::CardError, ::Stripe::InvalidRequestError, ::Stripe::PermissionError => e
          # NOTE: Do not mark the invoice as failed if the amount is too small for Stripe
          #       For now we keep it as pending, the user can still update it manually
          if e.code == "amount_too_small"
            return prepare_failed_result(e, payable_payment_status: :pending)
          end

          prepare_failed_result(e)
        rescue ::Stripe::IdempotencyError => e
          prepare_failed_result(e, payable_payment_status: :pending)
        rescue ::Stripe::RateLimitError => e
          # Allow auto-retry with idempotency key
          raise Invoices::Payments::RateLimitError, e
        rescue ::Stripe::APIConnectionError => e
          # Allow auto-retry with idempotency key
          raise Invoices::Payments::ConnectionError, e
        rescue ::Stripe::StripeError => e
          prepare_failed_result(e, reraise: true)
        end

        private

        attr_reader :payment, :reference, :metadata, :invoice, :provider_customer

        delegate :payment_provider, to: :provider_customer

        def handle_requires_action(payment)
          SendWebhookJob.perform_later("payment.requires_action", payment, {
            provider_customer_id: provider_customer.provider_customer_id
          })
        end

        def stripe_payment_method
          payment_method_id = provider_customer.payment_method_id

          if payment_method_id
            # NOTE: Check if payment method still exists
            check_result = PaymentProviderCustomers::Stripe::CheckPaymentMethodService.call(
              stripe_customer: provider_customer,
              payment_method_id:
            )
            return check_result.payment_method.id if check_result.success?
          end

          # NOTE: Retrieve list of existing payment_methods
          payment_method = ::Stripe::PaymentMethod.list(
            {customer: provider_customer.provider_customer_id},
            {api_key: payment_provider.secret_key}
          ).first
          provider_customer.update!(payment_method_id: payment_method&.id)

          payment_method&.id
        end

        def update_payment_method_id
          result = ::Stripe::Customer.retrieve(
            provider_customer.provider_customer_id,
            {api_key: payment_provider.secret_key}
          )

          # TODO: stripe customer should be updated/deleted
          # TODO: deliver error webhook
          # TODO(payment): update payment status
          return if result.deleted?

          if (payment_method_id = result.invoice_settings.default_payment_method || result.default_source)
            provider_customer.update!(payment_method_id:)
          end
        end

        def create_payment_intent
          update_payment_method_id

          ::Stripe::PaymentIntent.create(
            payment_intent_payload,
            {
              api_key: payment_provider.secret_key,
              idempotency_key: "payment-#{payment.id}"
            }
          )
        end

        def payment_intent_payload
          payload = {
            amount: payment.amount_cents,
            currency: payment.amount_currency.downcase,
            customer: provider_customer.provider_customer_id,
            payment_method: stripe_payment_method,
            payment_method_types: provider_customer.provider_payment_methods,
            confirm: true,
            off_session: off_session?,
            return_url: success_redirect_url,
            error_on_requires_action: error_on_requires_action?,
            description: reference,
            metadata: metadata
          }
          payload.merge!(customer_balance_fields) if provider_customer.provider_payment_methods == ["customer_balance"]
          payload
        end

        def customer_balance_fields
          {
            payment_method_data: {type: "customer_balance"},
            payment_method_options: {
              customer_balance: {
                funding_type: "bank_transfer",
                bank_transfer: bank_transfer_type
              }
            }
          }
        end

        def bank_transfer_type
          currency = payment.amount_currency.downcase
          return handle_eu_bank_transfer if currency == "eur"

          case currency
          when "usd" then {type: "us_bank_transfer"}
          when "gbp" then {type: "gb_bank_transfer"}
          when "jpy" then {type: "jp_bank_transfer"}
          when "mxn" then {type: "mx_bank_transfer"}
          else
            result.service_failure!(
              code: "stripe_error",
              message: "customer_balance is not supported for currency: #{currency}"
            )
          end
        end

        def handle_eu_bank_transfer
          allowed_countries = %w[BE DE ES FR IE NL]
          customer_country = payment.customer.country.upcase

          unless allowed_countries.include?(customer_country)
            return result.service_failure!(
              code: "stripe_error",
              message: "EU bank transfer is not supported for country: #{customer_country}"
            )
          end

          {type: "eu_bank_transfer", eu_bank_transfer: {country: customer_country}}
        end

        def success_redirect_url
          payment_provider.success_redirect_url.presence || ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
        end

        # NOTE: Due to RBI limitation, all indians payment should be off_session
        # to permit 3D secure authentication
        # https://docs.stripe.com/india-recurring-payments
        def off_session?
          return false if provider_customer.provider_payment_methods == ["customer_balance"]
          invoice.customer.country != "IN"
        end

        # NOTE: Same as off_session?
        def error_on_requires_action?
          invoice.customer.country != "IN"
        end

        def prepare_failed_result(error, reraise: false, payable_payment_status: :failed)
          result.error_message = error.message
          result.error_code = error.code
          result.reraise = reraise

          payment.update!(status: :failed, payable_payment_status:)

          result.service_failure!(code: "stripe_error", message: error.message)
        end
      end
    end
  end
end
