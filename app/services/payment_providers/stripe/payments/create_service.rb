# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class CreateService < BaseService
        PENDING_STATUSES = %w[processing requires_capture requires_action requires_confirmation requires_payment_method]
          .freeze
        SUCCESS_STATUSES = %w[succeeded].freeze
        FAILED_STATUSES = %w[canceled].freeze

        def initialize(payment:)
          @payment = payment
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          stripe_result = create_payment_intent

          payment.provider_payment_id = stripe_result.id
          payment.status = stripe_result.status
          payment.provider_payment_data = stripe_result.next_action if stripe_result.status == "requires_action"
          payment.save!

          handle_requires_action(payment) if payment.status == "requires_action"

          result.payment_status = payment_status_mapping(payment.status)
          result.payment = payment
          result

        # TODO: global refactor of the error handling
        # reprocessable errors shoud let the payment status to pending
        # identified errors should mark it as failed to allow reprocess via a new payment
        rescue ::Stripe::AuthenticationError, ::Stripe::CardError, ::Stripe::InvalidRequestError, ::Stripe::PermissionError => e
          # NOTE: Do not mark the invoice as failed if the amount is too small for Stripe
          #       For now we keep it as pending, the user can still update it manually
          return result if e.code == "amount_too_small"

          result.error_message = e.message
          result.error_code = e.code
          result.payment_status = :failed
          result
        rescue ::Stripe::RateLimitError => e
          raise Invoices::Payments::RateLimitError, e
        rescue ::Stripe::APIConnectionError => e
          raise Invoices::Payments::ConnectionError, e
        rescue ::Stripe::StripeError => e
          result.error_message = e.message
          result.error_code = e.code
          result.service_failure!(code: "stripe_error", message: e.message)
        end

        private

        attr_reader :payment, :invoice, :provider_customer

        delegate :payment_provider, to: :provider_customer

        def payment_status_mapping(payment_status)
          return :pending if PENDING_STATUSES.include?(payment_status)
          return :succeeded if SUCCESS_STATUSES.include?(payment_status)
          return :failed if FAILED_STATUSES.include?(payment_status)

          payment_status
        end

        def handle_requires_action(payment)
          SendWebhookJob.perform_later("payment.requires_action", payment, {
            provider_customer_id: provider_customer.provider_customer_id
          })
        end

        def stripe_payment_method
          payment_method_id = provider_customer.payment_method_id

          if payment_method_id
            # NOTE: Check if payment method still exists
            customer_service = PaymentProviderCustomers::StripeService.new(provider_customer)
            customer_service_result = customer_service.check_payment_method(payment_method_id)
            return customer_service_result.payment_method.id if customer_service_result.success?
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
          {
            amount: invoice.total_amount_cents,
            currency: invoice.currency.downcase,
            customer: provider_customer.provider_customer_id,
            payment_method: stripe_payment_method,
            payment_method_types: provider_customer.provider_payment_methods,
            confirm: true,
            off_session: off_session?,
            return_url: success_redirect_url,
            error_on_requires_action: error_on_requires_action?,
            description:,
            metadata: {
              lago_customer_id: provider_customer.customer_id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type
            }
          }
        end

        def success_redirect_url
          payment_provider.success_redirect_url.presence || ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
        end

        # NOTE: Due to RBI limitation, all indians payment should be off_session
        # to permit 3D secure authentication
        # https://docs.stripe.com/india-recurring-payments
        def off_session?
          invoice.customer.country != "IN"
        end

        # NOTE: Same as off_session?
        def error_on_requires_action?
          invoice.customer.country != "IN"
        end

        def description
          "#{invoice.organization.name} - Invoice #{invoice.number}"
        end
      end
    end
  end
end
