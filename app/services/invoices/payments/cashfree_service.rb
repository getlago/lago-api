# frozen_string_literal: true

module Invoices
  module Payments
    class CashfreeService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[PARTIALLY_PAID].freeze
      SUCCESS_STATUSES = %w[PAID].freeze
      FAILED_STATUSES = %w[EXPIRED CANCELLED].freeze

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

        # NOTE: No need to register the payment with Cashfree Payments for the Payment Link feature.
        # Simply create a single `Payment` record and update it upon receiving the webhook, which works perfectly fine.
        payment = Payment.new(
          payable: invoice,
          payment_provider_id: cashfree_payment_provider.id,
          payment_provider_customer_id: customer.cashfree_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency.upcase,
          provider_payment_id: invoice.id,
          status: :pending
        )
        payment.save!

        result.payment = payment
        result
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: 'cashfree_payment') unless payment

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        invoice_payment_status = invoice_payment_status(status)

        payment.update!(status: invoice_payment_status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?

        res = create_post_request(payment_url_params)

        result.payment_url = JSON.parse(res.body)["link_url"]

        result
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)
        result.service_failure!(code: e.error_code, message: e.error_body)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if cashfree_payment_provider.blank?

        customer&.cashfree_customer&.id
      end

      def client
        @client ||= LagoHttpClient::Client.new(::PaymentProviders::CashfreeProvider::BASE_URL)
      end

      def create_post_request(body)
        client.post_with_response(body, {
          "accept" => 'application/json',
          "content-type" => 'application/json',
          "x-client-id" => cashfree_payment_provider.client_id,
          "x-client-secret" => cashfree_payment_provider.client_secret,
          "x-api-version" => ::PaymentProviders::CashfreeProvider::API_VERSION
        })
      end

      def success_redirect_url
        cashfree_payment_provider.success_redirect_url.presence || ::PaymentProviders::CashfreeProvider::SUCCESS_REDIRECT_URL
      end

      def cashfree_payment_provider
        @cashfree_payment_provider ||= payment_provider(customer)
      end

      def payment_url_params
        {
          customer_details: {
            customer_phone: customer.phone || "9999999999",
            customer_email: customer.email,
            customer_name: customer.name
          },
          link_notify: {
            send_sms: false,
            send_email: false
          },
          link_meta: {
            upi_intent: true,
            return_url: success_redirect_url
          },
          link_notes: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601
          },
          link_id: "#{SecureRandom.uuid}.#{invoice.payment_attempts}",
          link_amount: invoice.total_amount_cents / 100.to_f,
          link_currency: invoice.currency.upcase,
          link_purpose: invoice.id,
          link_expiry_time: (Time.current + 10.minutes).iso8601,
          link_partial_payments: false,
          link_auto_reminders: false
        }
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
        @invoice = result.invoice
        result = Invoices::UpdateService.call(
          invoice:,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(cashfree_error)
        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: customer.cashfree_customer.provider_customer_id,
          provider_error: {
            message: cashfree_error.error_body,
            error_code: cashfree_error.error_code
          }
        })
      end
    end
  end
end
