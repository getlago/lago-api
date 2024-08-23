# frozen_string_literal: true

module PaymentRequests
  module Payments
    class StripeService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[processing requires_capture requires_action requires_confirmation requires_payment_method]
        .freeze
      SUCCESS_STATUSES = %w[succeeded].freeze
      FAILED_STATUSES = %w[canceled].freeze

      def initialize(payable = nil)
        @payable = payable

        super(nil)
      end

      def create
        result.payable = payable
        return result unless should_process_payment?

        unless payable.total_amount_cents.positive?
          update_payable_payment_status(payment_status: :succeeded)
          return result
        end

        payable.increment_payment_attempts!

        stripe_result = create_stripe_payment
        # NOTE: return if payment was not processed
        return result unless stripe_result

        payment = Payment.new(
          payable: payable,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          provider_payment_id: stripe_result.id,
          status: stripe_result.status
        )
        payment.save!

        update_payable_payment_status(
          payment_status: payable_payment_status(payment.status),
          processing: payment.status == 'processing'
        )
        update_invoices_payment_status(
          payment_status: payable_payment_status(payment.status),
          processing: payment.status == 'processing'
        )

        result.payment = payment
        result
      rescue Stripe::AuthenticationError, Stripe::CardError, Stripe::InvalidRequestError, Stripe::PermissionError => e
        # NOTE: Do not mark the payable as failed if the amount is too small for Stripe
        #       For now we keep it as pending.
        return result if e.code == 'amount_too_small'

        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)
        result
      rescue Stripe::RateLimitError, Stripe::APIConnectionError
        raise # Let the auto-retry process do its own job
      rescue Stripe::StripeError => e
        deliver_error_webhook(e)
        raise
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def success_redirect_url
        stripe_payment_provider.success_redirect_url.presence ||
          ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
      end

      def should_process_payment?
        return false if payable.payment_succeeded?
        return false if stripe_payment_provider.blank?

        !!customer&.stripe_customer&.provider_customer_id
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
      end

      def create_stripe_payment
        update_payment_method_id

        Stripe::PaymentIntent.create(
          stripe_payment_payload,
          {
            api_key: stripe_api_key,
            idempotency_key: "#{payable.id}/#{payable.payment_attempts}"
          }
        )
      end

      def stripe_payment_payload
        {
          amount: payable.total_amount_cents,
          currency: payable.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: stripe_payment_method,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          off_session: true,
          error_on_requires_action: true,
          description:,
          metadata: {
            lago_customer_id: customer.id,
            lago_payment_request_id: payable.id,
            lago_invoice_ids: payable.invoice_ids
          }
        }
      end

      def description
        # TODO: for invoices we define the payment description with the
        #       invoice number, however, we do no have this kind of identifiers
        #       on payment requests...
        #
        # "#{organization.name} - PaymentRequest #{payable.number}"

        "#{organization.name} - PaymentRequest 123"
      end

      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status&.to_sym
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true, processing: false)
        payable.update!(
          payment_status:,
          # NOTE: A proper `processing` payment status should be introduced for payment_requests
          ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
        )
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true, processing: false)
        payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice: invoice,
            params: {
              payment_status:,
              # NOTE: A proper `processing` payment status should be introduced for invoices
              ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def deliver_error_webhook(stripe_error)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: stripe_error.message,
            error_code: stripe_error.code
          }
        })
      end

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
