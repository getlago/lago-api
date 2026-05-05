# frozen_string_literal: true

module PaymentRequests
  module Payments
    class PaystackService < BaseService
      include Customers::PaymentProviderFinder
      include Updatable

      PROVIDER_NAME = "Paystack"

      def initialize(payable = nil)
        @payable = payable

        super(nil)
      end

      def generate_payment_url
        return unsupported_currency_result unless supported_currency?(payable.currency)

        paystack_result = client.initialize_transaction(payment_url_payload)
        result.payment_url = paystack_result.dig("data", "authorization_url")
        result
      rescue ::PaymentProviders::Paystack::Client::Error => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.code, error_message: e.message)
      rescue LagoHttpClient::HttpError => e
        result.third_party_failure!(third_party: PROVIDER_NAME, error_code: e.error_code, error_message: e.error_body)
      end

      def update_payment_status(organization_id:, status:, paystack_payment:)
        payment = Payment.find_by(provider_payment_id: paystack_payment.id)
        return result if payment&.payable&.organization_id.present? && payment.payable.organization_id != organization_id

        if !payment && paystack_payment.metadata[:payment_type] == "one-time"
          payment = create_payment(paystack_payment)
        end

        payment ||= handle_missing_payment(organization_id, paystack_payment)
        return result unless payment

        if payment.payable.payment_succeeded?
          result.payment = payment if payment.persisted?
          result.payable = payment.payable if payment.persisted?
          return result
        end

        payment.status = status
        payment.payable_payment_status = payment.payment_provider&.payable_payment_status(payment.status)
        payment.provider_payment_id = paystack_payment.id
        payment.provider_payment_data = provider_payment_data(paystack_payment)
        payment.save!

        result.payment = payment
        result.payable = payment.payable

        update_payment_method(paystack_payment.authorization) if payment.payable_payment_status == "succeeded"

        processing = payment.payable_payment_status.to_s == "processing"
        update_payable_payment_status(payment_status: payment.payable_payment_status, processing:)
        update_invoices_payment_status(payment_status: payment.payable_payment_status, processing:)
        update_invoices_paid_amount_cents(payment_status: payment.payable_payment_status)
        reset_customer_dunning_campaign_status(payment.payable_payment_status)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ActiveRecord::RecordNotUnique
        payment = Payment.find_by(provider_payment_id: paystack_payment.id)
        result.payment = payment if payment
        result.payable = payment.payable if payment
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def payment_url_payload
        {
          amount: payable.total_amount_cents,
          email: customer.email&.strip&.split(",")&.first,
          currency: payable.currency.upcase,
          reference: "lago-payment-request-#{payable.id}-#{SecureRandom.hex(6)}",
          callback_url: success_redirect_url,
          metadata: {
            lago_customer_id: customer.id,
            lago_payable_id: payable.id,
            lago_payable_type: payable.class.name,
            lago_invoice_ids: payable.invoices.pluck(:id).join(","),
            lago_organization_id: organization.id,
            lago_payment_provider_id: paystack_payment_provider.id,
            lago_payment_provider_code: paystack_payment_provider.code,
            payment_type: "one-time"
          }.to_json
        }
      end

      def create_payment(paystack_payment, payable: nil)
        @payable = payable || PaymentRequest.find_by(id: paystack_payment.metadata[:lago_payable_id])

        unless @payable
          result.not_found_failure!(resource: "payment_request")
          return
        end

        @payable.increment_payment_attempts!

        Payment.new(
          organization_id: @payable.organization_id,
          payable: @payable,
          customer:,
          payment_provider_id: paystack_payment_provider.id,
          payment_provider_customer_id: customer.paystack_customer.id,
          amount_cents: @payable.total_amount_cents,
          amount_currency: @payable.currency,
          provider_payment_id: paystack_payment.id,
          provider_payment_data: provider_payment_data(paystack_payment)
        )
      end

      def handle_missing_payment(organization_id, paystack_payment)
        if paystack_payment.metadata[:lago_payment_id].present?
          payment = Payment.find_by(id: paystack_payment.metadata[:lago_payment_id], organization_id:)
          return payment if payment
        end

        return unless paystack_payment.metadata&.key?(:lago_payable_id)

        payment_request = PaymentRequest.find_by(id: paystack_payment.metadata[:lago_payable_id], organization_id:)
        return unless payment_request
        return if payment_request.payment_failed?

        create_payment(paystack_payment, payable: payment_request)
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
          organization_id: result.payable.organization_id,
          customer_id: result.payable.customer_id,
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
          lago_customer_id: result.payable.customer_id,
          lago_payable_id: result.payable.id,
          lago_payable_type: result.payable.class.name,
          lago_organization_id: result.payable.organization_id
        }
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true, processing: false)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result.payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice:,
            params: {
              payment_status:,
              ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status.to_sym == :succeeded
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign!
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
