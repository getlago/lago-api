# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def update_payment_status(organization_id:, status:, stripe_payment:)
        payment = Payment.find_by(provider_payment_id: stripe_payment.id)

        if !payment && stripe_payment.metadata[:payment_type] == "one-time"
          payment = create_payment(stripe_payment)
        end

        unless payment
          handle_missing_payment(organization_id, stripe_payment)
          return result unless result.payment

          payment = result.payment
        end

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.status = status

        payable_payment_status = payment.payment_provider&.determine_payment_status(payment.status)
        payment.payable_payment_status = payable_payment_status
        payment.save!

        update_invoice_payment_status(
          payment_status: payable_payment_status,
          processing: status == "processing"
        )

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?

        res = ::Stripe::Checkout::Session.create(
          payment_url_payload,
          {
            api_key: stripe_api_key
          }
        )

        result.payment_url = res["url"]

        result
      rescue ::Stripe::CardError, ::Stripe::InvalidRequestError, ::Stripe::AuthenticationError, Stripe::PermissionError => e
        deliver_error_webhook(e)

        result.single_validation_failure!(error_code: "payment_provider_error")
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def create_payment(stripe_payment, invoice: nil)
        @invoice = invoice || Invoice.find_by(id: stripe_payment.metadata[:lago_invoice_id])
        unless @invoice
          result.not_found_failure!(resource: "invoice")
          return
        end

        increment_payment_attempts

        payment = Payment.find_or_initialize_by(
          payable: @invoice,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: @invoice.total_amount_cents,
          amount_currency: @invoice.currency,
          status: "pending"
        )

        status = payment.payment_provider&.determine_payment_status(stripe_payment.status)
        status = (status.to_sym == :pending) ? :processing : status

        payment.provider_payment_id = stripe_payment.id
        payment.status = stripe_payment.status
        payment.payable_payment_status = status
        payment.save!
        payment
      end

      def success_redirect_url
        stripe_payment_provider.success_redirect_url.presence ||
          ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
      end

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if stripe_payment_provider.blank?

        customer&.stripe_customer&.provider_customer_id
      end

      def stripe_api_key
        stripe_payment_provider.secret_key
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
          mode: "payment",
          success_url: success_redirect_url,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          payment_intent_data: {
            description:,
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type,
              payment_type: "one-time"
            }
          }
        }
      end

      def description
        "#{organization.name} - Invoice #{invoice.number}"
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
        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: stripe_error.message,
            error_code: stripe_error.code
          }
        })
      end

      def handle_missing_payment(organization_id, stripe_payment)
        # NOTE: Payment was not initiated by lago
        return result unless stripe_payment.metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belong to this lago organization
        #       It means the same Stripe secret key is used for multiple organizations
        invoice = Invoice.find_by(id: stripe_payment.metadata[:lago_invoice_id], organization_id:)
        return result if invoice.nil?

        # NOTE: Invoice exists but payment status is failed
        return result if invoice.payment_failed?

        # NOTE: For some reason payment is missing in the database... (killed sidekiq job, etc.)
        #       We have to recreate it from the received data
        result.payment = create_payment(stripe_payment, invoice:)
        result
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

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
