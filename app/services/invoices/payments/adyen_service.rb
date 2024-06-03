# frozen_string_literal: true

module Invoices
  module Payments
    class AdyenService < BaseService
      include Lago::Adyen::ErrorHandlable
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[AuthorisedPending Received].freeze
      SUCCESS_STATUSES = %w[Authorised SentForSettle SettleScheduled Settled Refunded].freeze
      FAILED_STATUSES = %w[Cancelled CaptureFailed Error Expired Refused].freeze

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

        res = create_adyen_payment
        return result unless res

        adyen_success, _adyen_error = handle_adyen_response(res)
        return result unless adyen_success

        payment = Payment.new(
          invoice:,
          payment_provider_id: adyen_payment_provider.id,
          payment_provider_customer_id: customer.adyen_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency.upcase,
          provider_payment_id: res.response['pspReference'],
          status: res.response['resultCode']
        )
        payment.save!

        invoice_payment_status = invoice_payment_status(payment.status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      end

      def update_payment_status(provider_payment_id:, status:, metadata: {})
        payment = if metadata[:payment_type] == 'one-time'
          create_payment(provider_payment_id:, metadata:)
        else
          Payment.find_by(provider_payment_id:)
        end
        return result.not_found_failure!(resource: 'adyen_payment') unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status:)

        invoice_payment_status = invoice_payment_status(status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?

        res = client.checkout.payment_links_api.payment_links(Lago::Adyen::Params.new(payment_url_params).to_h)
        adyen_success, adyen_error = handle_adyen_response(res)
        result.service_failure!(code: adyen_error.code, message: adyen_error.msg) unless adyen_success

        return result unless result.success?

        result.payment_url = res.response['url']

        result
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)

        result.service_failure!(code: e.code, message: e.msg)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def create_payment(provider_payment_id:, metadata:)
        @invoice = Invoice.find(metadata[:lago_invoice_id])

        increment_payment_attempts

        Payment.new(
          invoice:,
          payment_provider_id: adyen_payment_provider.id,
          payment_provider_customer_id: customer.adyen_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency.upcase,
          provider_payment_id:
        )
      end

      def should_process_payment?
        return false if invoice.succeeded? || invoice.voided?
        return false if adyen_payment_provider.blank?

        customer&.adyen_customer&.provider_customer_id
      end

      def client
        @client ||= Adyen::Client.new(
          api_key: adyen_payment_provider.api_key,
          env: adyen_payment_provider.environment,
          live_url_prefix: adyen_payment_provider.live_prefix
        )
      end

      def success_redirect_url
        adyen_payment_provider.success_redirect_url.presence || ::PaymentProviders::AdyenProvider::SUCCESS_REDIRECT_URL
      end

      def adyen_payment_provider
        @adyen_payment_provider ||= payment_provider(customer)
      end

      def update_payment_method_id
        result = client.checkout.payments_api.payment_methods(
          Lago::Adyen::Params.new(payment_method_params).to_h
        ).response

        payment_method_id = result['storedPaymentMethods']&.first&.dig('id')
        customer.adyen_customer.update!(payment_method_id:) if payment_method_id
      end

      def create_adyen_payment
        update_payment_method_id

        client.checkout.payments_api.payments(Lago::Adyen::Params.new(payment_params).to_h)
      rescue Adyen::AuthenticationError, Adyen::ValidationError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)
        nil
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)
        raise e
      end

      def payment_method_params
        {
          merchantAccount: adyen_payment_provider.merchant_account,
          shopperReference: customer.adyen_customer.provider_customer_id
        }
      end

      def payment_params
        prms = {
          amount: {
            currency: invoice.currency.upcase,
            value: invoice.total_amount_cents
          },
          reference: invoice.number,
          paymentMethod: {
            type: 'scheme',
            storedPaymentMethodId: customer.adyen_customer.payment_method_id
          },
          shopperReference: customer.adyen_customer.provider_customer_id,
          merchantAccount: adyen_payment_provider.merchant_account,
          shopperInteraction: 'ContAuth',
          recurringProcessingModel: 'UnscheduledCardOnFile'
        }
        prms[:shopperEmail] = customer.email if customer.email
        prms
      end

      def payment_url_params
        prms = {
          reference: invoice.number,
          amount: {
            value: invoice.total_amount_cents,
            currency: invoice.currency.upcase
          },
          merchantAccount: adyen_payment_provider.merchant_account,
          returnUrl: success_redirect_url,
          shopperReference: customer.external_id,
          storePaymentMethodMode: 'enabled',
          recurringProcessingModel: 'UnscheduledCardOnFile',
          expiresAt: Time.current + 1.day,
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type,
            payment_type: 'one-time'
          }
        }
        prms[:shopperEmail] = customer.email if customer.email
        prms
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
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

      def deliver_error_webhook(adyen_error)
        return unless invoice.organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.adyen_customer.provider_customer_id,
          provider_error: {
            message: adyen_error.msg,
            error_code: adyen_error.code
          }
        )
      end
    end
  end
end
