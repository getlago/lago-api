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

        payable_payment_status = payable_payment_status(payment.status)
        update_payable_payment_status(
          payment_status: payable_payment_status,
          processing: payment.status == "processing"
        )
        update_invoices_payment_status(
          payment_status: payable_payment_status,
          processing: payment.status == "processing"
        )

        result.payment = payment
        result
      rescue ::Stripe::AuthenticationError, ::Stripe::CardError, ::Stripe::InvalidRequestError, Stripe::PermissionError => e
        # NOTE: Do not mark the payable as failed if the amount is too small for Stripe
        #       For now we keep it as pending.
        return result if e.code == "amount_too_small"

        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)
        result
      rescue ::Stripe::RateLimitError, ::Stripe::APIConnectionError
        raise # Let the auto-retry process do its own job
      rescue ::Stripe::StripeError => e
        deliver_error_webhook(e)
        raise
      end

      def generate_payment_url
        return result unless should_process_payment?

        result_url = ::Stripe::Checkout::Session.create(
          payment_url_payload,
          {
            api_key: stripe_api_key
          }
        )

        result.payment_url = result_url["url"]

        result
      rescue ::Stripe::CardError, ::Stripe::InvalidRequestError, ::Stripe::AuthenticationError, Stripe::PermissionError => e
        deliver_error_webhook(e)

        result.single_validation_failure!(error_code: "payment_provider_error")
      end

      def update_payment_status(organization_id:, status:, stripe_payment:)
        # TODO: do we have one-time payments for payment requests?
        payment = if stripe_payment.metadata[:payment_type] == "one-time"
          create_payment(stripe_payment)
        else
          Payment.find_by(provider_payment_id: stripe_payment.id)
        end

        unless payment
          handle_missing_payment(organization_id, stripe_payment)
          return result unless result.payment

          payment = result.payment
        end

        result.payment = payment
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        processing = status == "processing"
        payment_status = payable_payment_status(status)
        update_payable_payment_status(payment_status:, processing:)
        update_invoices_payment_status(payment_status:, processing:)
        reset_customer_dunning_campaign_status(payment_status)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
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
            lago_payable_id: payable.id,
            lago_payable_type: payable.class.name
          }
        }
      end

      def description
        "#{organization.name} - Overdue invoices"
      end

      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status&.to_sym
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true, processing: false)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            # NOTE: A proper `processing` payment status should be introduced for payment_requests
            ready_for_payment_processing: !processing && !payment_status_succeeded?(payment_status)
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result.payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice: invoice,
            params: {
              payment_status:,
              # NOTE: A proper `processing` payment status should be introduced for invoices
              ready_for_payment_processing: !processing && !payment_status_succeeded?(payment_status)
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def payment_url_payload
        {
          line_items: [
            {
              quantity: 1,
              price_data: {
                currency: payable.currency.downcase,
                unit_amount: payable.total_amount_cents,
                product_data: {
                  name: "Overdue invoices"
                }
              }
            }
          ],
          mode: "payment",
          success_url: success_redirect_url,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          payment_intent_data: {
            description:,
            metadata: {
              lago_customer_id: customer.id,
              lago_payable_id: payable.id,
              lago_payable_type: payable.class.name,
              payment_type: "one-time"
            }
          }
        }
      end

      def handle_missing_payment(organization_id, stripe_payment)
        # NOTE: Payment was not initiated by lago
        return result unless stripe_payment.metadata&.key?(:lago_payable_id)

        # NOTE: Payment Request does not belong to this lago organization
        #       It means the same Stripe secret key is used for multiple organizations
        payment_request = PaymentRequest.find_by(id: stripe_payment.metadata[:lago_payable_id], organization_id:)
        return result unless payment_request

        # NOTE: Payment Request exists but payment status is failed
        return result if payment_request.payment_failed?

        # NOTE: For some reason payment is missing in the database... (killed sidekiq job, etc.)
        #       We have to recreate it from the received data
        result.payment = create_payment(stripe_payment, payable: payment_request)
        result
      end

      def create_payment(stripe_payment, payable: nil)
        @payable = payable || PaymentRequest.find_by(id: stripe_payment.metadata[:lago_payable_id])

        unless @payable
          result.not_found_failure!(resource: "payment_request")
          return
        end

        @payable.increment_payment_attempts!

        Payment.new(
          payable: @payable,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: @payable.total_amount_cents,
          amount_currency: @payable.currency,
          provider_payment_id: stripe_payment.id
        )
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

      def payment_status_succeeded?(payment_status)
        payment_status.to_sym == :succeeded
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status_succeeded?(payment_status)
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign!
      end
    end
  end
end
