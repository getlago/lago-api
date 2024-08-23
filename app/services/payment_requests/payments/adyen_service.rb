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
          provider_payment_id: res.response['pspReference'],
          status: res.response['resultCode']
        )
        payment.save!

        payable_payment_status = payable_payment_status(payment.status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
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

        payment_method_id = result['storedPaymentMethods']&.first&.dig('id')
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
          reference: payable.id,
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

      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true)
        payable.update!(
          payment_status:,
          ready_for_payment_processing: payment_status.to_sym != :succeeded
        )
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
