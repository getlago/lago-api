# frozen_string_literal: true

module PaymentRequests
  module Payments
    class AdyenService < BaseService
      include Lago::Adyen::ErrorHandlable
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[AuthorisedPending Received].freeze
      SUCCESS_STATUSES = %w[Authorised SentForSettle SettleScheduled Settled Refunded].freeze
      FAILED_STATUSES = %w[Cancelled CaptureFailed Error Expired Refused].freeze

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

        res = create_adyen_payment
        return result unless res

        adyen_success, _adyen_error = handle_adyen_response(res)
        return result unless adyen_success

        payment = Payment.new(
          payable: payable,
          payment_provider_id: adyen_payment_provider.id,
          payment_provider_customer_id: customer.adyen_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency.upcase,
          provider_payment_id: res.response["pspReference"],
          status: res.response["resultCode"]
        )

        ActiveRecord::Base.transaction do
          payment.save!

          payable_payment_status = payable_payment_status(payment.status)
          update_payable_payment_status(payment_status: payable_payment_status)
          update_invoices_payment_status(payment_status: payable_payment_status)
        end

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      end

      def generate_payment_url
        return result unless should_process_payment?

        result_url = client.checkout.payment_links_api.payment_links(
          Lago::Adyen::Params.new(payment_url_params).to_h
        )

        adyen_success, adyen_error = handle_adyen_response(result_url)
        return result.service_failure!(code: adyen_error.code, message: adyen_error.msg) unless adyen_success

        result.payment_url = result_url.response["url"]

        result
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)

        result.service_failure!(code: e.code, message: e.msg)
      end

      def update_payment_status(provider_payment_id:, status:, metadata: {})
        payment = if metadata[:payment_type] == "one-time"
          create_payment(provider_payment_id:, metadata:)
        else
          Payment.find_by(provider_payment_id:)
        end
        return result.not_found_failure!(resource: "adyen_payment") unless payment

        result.payment = payment
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        payable_payment_status = payable_payment_status(status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def should_process_payment?
        return false if payable.payment_succeeded?
        return false if adyen_payment_provider.blank?

        !!customer&.adyen_customer&.provider_customer_id
      end

      def client
        @client ||= Adyen::Client.new(
          api_key: adyen_payment_provider.api_key,
          env: adyen_payment_provider.environment,
          live_url_prefix: adyen_payment_provider.live_prefix
        )
      end

      def adyen_payment_provider
        @adyen_payment_provider ||= payment_provider(customer)
      end

      def update_payment_method_id
        result = client.checkout.payments_api.payment_methods(
          Lago::Adyen::Params.new(payment_method_params).to_h
        ).response

        payment_method_id = result["storedPaymentMethods"]&.first&.dig("id")
        customer.adyen_customer.update!(payment_method_id:) if payment_method_id
      end

      def create_adyen_payment
        update_payment_method_id

        client.checkout.payments_api.payments(Lago::Adyen::Params.new(payment_params).to_h)
      rescue Adyen::AuthenticationError, Adyen::ValidationError => e
        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)
        nil
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)
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
            currency: payable.currency.upcase,
            value: payable.total_amount_cents
          },
          reference: "Overdue invoices",
          paymentMethod: {
            type: "scheme",
            storedPaymentMethodId: customer.adyen_customer.payment_method_id
          },
          shopperReference: customer.adyen_customer.provider_customer_id,
          merchantAccount: adyen_payment_provider.merchant_account,
          shopperInteraction: "ContAuth",
          recurringProcessingModel: "UnscheduledCardOnFile"
        }
        prms[:shopperEmail] = customer.email if customer.email
        prms
      end

      def payment_url_params
        prms = {
          reference: "Overdue invoices",
          amount: {
            value: payable.total_amount_cents,
            currency: payable.currency.upcase
          },
          merchantAccount: adyen_payment_provider.merchant_account,
          returnUrl: success_redirect_url,
          shopperReference: customer.external_id,
          storePaymentMethodMode: "enabled",
          recurringProcessingModel: "UnscheduledCardOnFile",
          expiresAt: Time.current + 70.days, # max link TTL
          metadata: {
            lago_customer_id: customer.id,
            lago_payment_request_id: payable.id,
            lago_invoice_ids: payable.invoice_ids,
            payment_type: "one-time"
          }
        }
        prms[:shopperEmail] = customer.email if customer.email
        prms
      end

      def success_redirect_url
        adyen_payment_provider.success_redirect_url.presence || ::PaymentProviders::AdyenProvider::SUCCESS_REDIRECT_URL
      end

      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true)
        payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice:,
            params: {
              payment_status:,
              ready_for_payment_processing: payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def create_payment(provider_payment_id:, metadata:)
        @payable = PaymentRequest.find(metadata[:lago_payment_request_id])

        payable.increment_payment_attempts!

        Payment.new(
          payable:,
          payment_provider_id: adyen_payment_provider.id,
          payment_provider_customer_id: customer.adyen_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency.upcase,
          provider_payment_id:
        )
      end

      def deliver_error_webhook(adyen_error)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: customer.adyen_customer.provider_customer_id,
          provider_error: {
            message: adyen_error.msg,
            error_code: adyen_error.code
          }
        })
      end
    end
  end
end
