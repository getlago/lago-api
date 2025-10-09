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
          SendWebhookJob.perform_later("payment.requires_action", payment)
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
          payment_method = ::Stripe::Customer.list_payment_methods(
            provider_customer.provider_customer_id,
            {},
            {api_key: payment_provider.secret_key}
          ).first
          provider_customer.update!(payment_method_id: payment_method&.id)

          payment_method&.id
        end

        def update_payment_method_id
          stripe_customer = ::Stripe::Customer.retrieve(
            provider_customer.provider_customer_id,
            {api_key: payment_provider.secret_key}
          )

          # TODO: stripe customer should be updated/deleted
          # TODO: deliver error webhook
          # TODO(payment): update payment status
          return if stripe_customer.deleted?

          if (payment_method_id = stripe_customer.invoice_settings.default_payment_method || stripe_customer.default_source)
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

        def enriched_metadata
          metadata.merge(
            {
              lago_payment_id: payment.id,
              lago_payable_id: payment.payable_id,
              lago_payable_type: payment.payable_type,
              lago_customer_id: payment.payable.customer_id,
              lago_organization_id: payment.payable.organization_id,
              lago_billing_entity_id: payment.payable.billing_entity.id
            }
          )
        end

        def payment_intent_payload
          payload = {
            amount: payment.amount_cents,
            currency: payment.amount_currency.downcase,
            customer: provider_customer.provider_customer_id,
            payment_method_types: provider_customer.provider_payment_methods,
            confirm: true,
            return_url: success_redirect_url,
            description: reference,
            metadata: enriched_metadata
          }

          if provider_customer.provider_payment_methods == ["customer_balance"]
            payload.merge!(customer_balance_fields)
          else
            payload[:payment_method] = stripe_payment_method
          end

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

          transfer_types = {
            "usd" => {type: "us_bank_transfer"},
            "gbp" => {type: "gb_bank_transfer"},
            "jpy" => {type: "jp_bank_transfer"},
            "mxn" => {type: "mx_bank_transfer"}
          }
          transfer_types[currency]
        end

        def handle_eu_bank_transfer
          customer_country = payment.customer.country&.upcase
          billing_entity_country = payment.customer.billing_entity.country&.upcase

          country =
            if PaymentProviders::StripeProvider::SUPPORTED_EU_BANK_TRANSFER_COUNTRIES.include?(customer_country)
              customer_country
            elsif PaymentProviders::StripeProvider::SUPPORTED_EU_BANK_TRANSFER_COUNTRIES.include?(billing_entity_country)
              billing_entity_country
            else
              result.service_failure!(
                code: "missing_country",
                message: "No country found for customer or organization supported for EU bank transfer payload"
              ).raise_if_error!
            end

          {
            type: "eu_bank_transfer",
            eu_bank_transfer: {country: country}
          }
        end

        def success_redirect_url
          payment_provider.success_redirect_url.presence || ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
        end

        def prepare_failed_result(error, reraise: false, payable_payment_status: :failed)
          result.error_message = error.message
          result.error_code = error.code
          result.reraise = reraise

          # stripe may return us a Stripe::CardError error if payment_intent was created, but it's processing failed, in this case error would contain payment_intent id
          payment.update!(status: :failed, payable_payment_status:, provider_payment_id: error.error&.payment_intent&.id)

          result.service_failure!(code: "stripe_error", message: error.message, error:)
        end
      end
    end
  end
end
