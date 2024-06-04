# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[processing requires_capture requires_action requires_confirmation requires_payment_method]
        .freeze
      SUCCESS_STATUSES = %w[succeeded].freeze
      FAILED_STATUSES = %w[canceled].freeze

      def initialize(invoice = nil)
        @invoice = invoice

        super(nil)
      end

      def create
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        increment_payment_attempts

        stripe_result = create_stripe_payment
        # NOTE: return if payment was not processed
        return result unless stripe_result

        payment = Payment.new(
          invoice:,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          provider_payment_id: stripe_result.id,
          status: stripe_result.status
        )
        payment.save!

        update_invoice_payment_status(
          payment_status: invoice_payment_status(payment.status),
          processing: payment.status == 'processing'
        )

        result.payment = payment
        result
      end

      def update_payment_status(organization_id:, provider_payment_id:, status:, metadata: {})
        payment = if metadata[:payment_type] == 'one-time'
          create_payment(provider_payment_id:, metadata:)
        else
          Payment.find_by(provider_payment_id:)
        end
        return handle_missing_payment(organization_id, metadata) unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status:)

        update_invoice_payment_status(
          payment_status: invoice_payment_status(status),
          processing: status == 'processing'
        )

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?

        res = Stripe::Checkout::Session.create(
          payment_url_payload,
          {
            api_key: stripe_api_key
          }
        )

        result.payment_url = res['url']

        result
      rescue Stripe::CardError, Stripe::InvalidRequestError, Stripe::AuthenticationError, Stripe::PermissionError => e
        deliver_error_webhook(e)

        result.single_validation_failure!(error_code: 'payment_provider_error')
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def create_payment(provider_payment_id:, metadata:)
        @invoice = Invoice.find_by(id: metadata[:lago_invoice_id])
        unless @invoice
          result.not_found_failure!(resource: 'invoice')
          return
        end

        increment_payment_attempts

        Payment.new(
          invoice:,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency&.upcase,
          provider_payment_id:
        )
      end

      def success_redirect_url
        stripe_payment_provider.success_redirect_url.presence ||
          ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
      end

      def should_process_payment?
        return false if invoice.succeeded? || invoice.voided?
        return false if stripe_payment_provider.blank?

        customer&.stripe_customer&.provider_customer_id
      end

      def stripe_api_key
        stripe_payment_provider.secret_key
      end

      def stripe_payment_method
        payment_method_id = customer.stripe_customer.payment_method_id

        if payment_method_id
          # NOTE: Check if payment method still exists
          customer_service = PaymentProviderCustomers::StripeService.new(customer.stripe_customer)
          customer_service_result = customer_service.check_payment_method(payment_method_id)
          return customer_service_result.payment_method.id if customer_service_result.success?
        end

        # NOTE: Retrieve list of existing payment_methods
        payment_method = Stripe::PaymentMethod.list(
          {
            customer: customer.stripe_customer.provider_customer_id
          },
          {
            api_key: stripe_api_key
          }
        ).first
        customer.stripe_customer.payment_method_id = payment_method&.id
        customer.stripe_customer.save!

        payment_method&.id
      end

      def update_payment_method_id
        result = Stripe::Customer.retrieve(
          customer.stripe_customer.provider_customer_id,
          {
            api_key: stripe_api_key
          }
        )
        # TODO: stripe customer should be updated/deleted
        return if result.deleted?

        if (payment_method_id = result.invoice_settings.default_payment_method || result.default_source)
          customer.stripe_customer.update!(payment_method_id:)
        end
      rescue Stripe::StripeError => e
        deliver_error_webhook(e)
        raise
      end

      def create_stripe_payment
        update_payment_method_id

        Stripe::PaymentIntent.create(
          stripe_payment_payload,
          {
            api_key: stripe_api_key,
            idempotency_key: "#{invoice.id}/#{invoice.payment_attempts}"
          }
        )
      rescue Stripe::CardError, Stripe::InvalidRequestError, Stripe::PermissionError => e
        # NOTE: Do not mark the invoice as failed if the amount is too small for Stripe
        #       For now we keep it as pending, the user can still update it manually
        return if e.code == 'amount_too_small'

        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)
        nil
      end

      def stripe_payment_payload
        {
          amount: invoice.total_amount_cents,
          currency: invoice.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: stripe_payment_method,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          off_session: true,
          error_on_requires_action: true,
          description: "#{organization.name} - Invoice #{invoice.number}",
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        }
      end

      def payment_url_payload
        {
          line_items: [
            {
              quantity: 1,
              price_data: {
                currency: invoice.currency.downcase,
                unit_amount: invoice.total_amount_cents,
                product_data: {
                  name: invoice.number
                }
              }
            }
          ],
          mode: 'payment',
          success_url: success_redirect_url,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          payment_intent_data: {
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type,
              payment_type: 'one-time'
            }
          }
        }
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status&.to_sym
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result = Invoices::UpdateService.call(
          invoice: invoice.presence || @result.invoice,
          params: {
            payment_status:,
            # NOTE: A proper `processing` payment status should be introduced for invoices
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(stripe_error)
        return unless invoice.organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: stripe_error.message,
            error_code: stripe_error.code
          }
        )
      end

      def handle_missing_payment(organization_id, metadata)
        # NOTE: Payment was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belong to this lago organization
        #       It means the same Stripe secret key is used for multiple organizations
        invoice = Invoice.find_by(id: metadata[:lago_invoice_id], organization_id:)
        return result if invoice.nil?

        # NOTE: Invoice exists but status is failed
        return result if invoice.failed?

        result.not_found_failure!(resource: 'stripe_payment')
      end

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
