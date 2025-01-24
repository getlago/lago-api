# frozen_string_literal: true

module Invoices
  module Payments
    class CashfreeService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def update_payment_status(organization_id:, status:, cashfree_payment:)
        payment = if cashfree_payment.metadata[:payment_type] == "one-time"
          create_payment(cashfree_payment)
        else
          Payment.find_by(provider_payment_id: cashfree_payment.id)
        end
        return result.not_found_failure!(resource: "cashfree_payment") unless payment

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.status = status

        payable_payment_status = payment.payment_provider&.determine_payment_status(payment.status)
        payment.payable_payment_status = payable_payment_status
        payment.save!

        update_invoice_payment_status(payment_status: payable_payment_status)

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?

        payment_link_response = create_payment_link(payment_url_params)
        result.payment_url = JSON.parse(payment_link_response.body)["link_url"]

        result
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)

        result.third_party_failure!(third_party: "Cashfree", error_message: e.error_body)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def create_payment(cashfree_payment)
        @invoice = Invoice.find_by(id: cashfree_payment.metadata[:lago_invoice_id])

        increment_payment_attempts

        Payment.new(
          payable: @invoice,
          payment_provider_id: cashfree_payment_provider.id,
          payment_provider_customer_id: customer.cashfree_customer.id,
          amount_cents: @invoice.total_amount_cents,
          amount_currency: @invoice.currency,
          provider_payment_id: cashfree_payment.id
        )
      end

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if cashfree_payment_provider.blank?

        !!customer&.cashfree_customer&.id
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def client
        @client ||= LagoHttpClient::Client.new(::PaymentProviders::CashfreeProvider::BASE_URL)
      end

      def create_payment_link(body)
        client.post_with_response(body, {
          "accept" => "application/json",
          "content-type" => "application/json",
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

      def deliver_error_webhook(cashfree_error)
        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: customer.cashfree_customer.id,
          provider_error: {
            message: cashfree_error.error_body,
            error_code: cashfree_error.error_code
          }
        })
      end
    end
  end
end
