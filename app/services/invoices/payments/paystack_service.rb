# frozen_string_literal: true

module Invoices
  module Payments
    class PaystackService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Paystack"

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def update_payment_status(organization_id:, status:, paystack_payment:)
        payment = Payment.find_by(provider_payment_id: paystack_payment.id)
        return result if payment&.payable&.organization_id.present? && payment.payable.organization_id != organization_id

        if !payment && paystack_payment.metadata[:payment_type] == "one-time"
          payment = create_payment(paystack_payment)
        end

        payment ||= handle_missing_payment(organization_id, paystack_payment)
        return result unless payment

        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.provider_payment_id = paystack_payment.id
        payment.status = status
        payment.payable_payment_status = payment.payment_provider&.payable_payment_status(payment.status)
        payment.provider_payment_data = provider_payment_data(paystack_payment)
        payment.save!

        update_payment_method(paystack_payment.authorization) if payment.payable_payment_status == "succeeded"
        deliver_webhook if payment.payable_payment_status.to_sym == :succeeded

        update_invoice_payment_status(
          payment_status: payment.payable_payment_status,
          processing: payment.payable_payment_status.to_s == "processing"
        )

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique
        payment = Payment.find_by(provider_payment_id: paystack_payment.id)
        result.payment = payment if payment
        result.invoice = payment.payable if payment
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url(payment_intent)
        return unsupported_currency_result unless supported_currency?(invoice.currency)

        paystack_result = client.initialize_transaction(payment_url_payload(payment_intent))
        result.payment_url = paystack_result.dig("data", "authorization_url")
        result
      rescue ::PaymentProviders::Paystack::Client::Error => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.code, error_message: e.message)
      rescue LagoHttpClient::HttpError => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def create_payment(paystack_payment, invoice: nil)
        @invoice = invoice || Invoice.find_by(id: paystack_payment.metadata[:lago_payable_id] || paystack_payment.metadata[:lago_invoice_id])
        unless @invoice
          result.not_found_failure!(resource: "invoice")
          return
        end

        increment_payment_attempts

        Payment.new(
          organization_id: @invoice.organization_id,
          payable: @invoice,
          customer:,
          payment_provider_id: paystack_payment_provider.id,
          payment_provider_customer_id: customer.paystack_customer.id,
          amount_cents: @invoice.total_due_amount_cents,
          amount_currency: @invoice.currency,
          provider_payment_id: paystack_payment.id,
          provider_payment_data: provider_payment_data(paystack_payment)
        )
      end

      def handle_missing_payment(organization_id, paystack_payment)
        if paystack_payment.metadata[:lago_payment_id].present?
          payment = Payment.find_by(id: paystack_payment.metadata[:lago_payment_id], organization_id:)
          return payment if payment
        end

        return unless paystack_payment.metadata&.key?(:lago_payable_id) || paystack_payment.metadata&.key?(:lago_invoice_id)

        invoice = Invoice.find_by(
          id: paystack_payment.metadata[:lago_payable_id] || paystack_payment.metadata[:lago_invoice_id],
          organization_id:
        )
        return if invoice.nil?
        return if invoice.payment_failed?

        create_payment(paystack_payment, invoice:)
      end

      def payment_url_payload(payment_intent)
        {
          amount: invoice.total_due_amount_cents,
          email: customer.email&.strip&.split(",")&.first,
          currency: invoice.currency.upcase,
          reference: "lago-invoice-#{payment_intent.id}",
          callback_url: success_redirect_url,
          metadata: {
            lago_customer_id: customer.id,
            lago_payable_id: invoice.id,
            lago_payable_type: invoice.class.name,
            lago_invoice_id: invoice.id,
            lago_invoice_number: invoice.number,
            lago_organization_id: organization.id,
            lago_payment_intent_id: payment_intent.id,
            lago_payment_provider_id: paystack_payment_provider.id,
            lago_payment_provider_code: paystack_payment_provider.code,
            payment_type: "one-time"
          }.to_json
        }
      end

      def provider_payment_data(paystack_payment)
        {
          reference: paystack_payment.reference,
          gateway_response: paystack_payment.gateway_response,
          amount: paystack_payment.amount,
          currency: paystack_payment.currency
        }.compact
      end

      def update_payment_method(authorization)
        return unless reusable_card_authorization?(authorization)

        PaymentProviderCustomers::PaystackService.new.update_payment_method(
          organization_id: result.invoice.organization_id,
          customer_id: result.invoice.customer_id,
          payment_method_id: authorization["authorization_code"],
          metadata: paystack_metadata.stringify_keys,
          card_details: card_details(authorization)
        ).raise_if_error!
      end

      def reusable_card_authorization?(authorization)
        authorization.present? &&
          authorization["authorization_code"].present? &&
          authorization["reusable"] == true &&
          authorization["channel"] == "card"
      end

      def card_details(authorization)
        {
          type: "card",
          last4: authorization["last4"],
          brand: authorization["brand"].presence || authorization["card_type"],
          expiration_month: authorization["exp_month"],
          expiration_year: authorization["exp_year"],
          issuer: authorization["bank"],
          country: authorization["country_code"]
        }.compact
      end

      def paystack_metadata
        {
          lago_customer_id: result.invoice.customer_id,
          lago_payable_id: result.invoice.id,
          lago_payable_type: result.invoice.class.name,
          lago_organization_id: result.invoice.organization_id
        }
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        params = {
          payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
          ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
        }

        if payment_status.to_sym == :succeeded
          total_paid_amount_cents = (invoice.presence || @result.invoice).payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
          params[:total_paid_amount_cents] = total_paid_amount_cents
        end

        Invoices::UpdateService.call!(
          invoice: invoice.presence || @result.invoice,
          params:,
          webhook_notification: deliver_webhook
        )
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_webhook
        SendWebhookJob.perform_later("payment.succeeded", result.payment)
      end

      def success_redirect_url
        paystack_payment_provider.success_redirect_url.presence ||
          ::PaymentProviders::PaystackProvider::SUCCESS_REDIRECT_URL
      end

      def client
        @client ||= ::PaymentProviders::Paystack::Client.new(payment_provider: paystack_payment_provider)
      end

      def paystack_payment_provider
        @paystack_payment_provider ||= payment_provider(customer)
      end

      def supported_currency?(currency)
        ::PaymentProviders::PaystackProvider.supported_currency?(currency)
      end

      def unsupported_currency_result
        result.single_validation_failure!(error_code: "unsupported_currency", field: :currency)
      end
    end
  end
end
