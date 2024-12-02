# frozen_string_literal: true

module PaymentRequests
  module Payments
    class CashfreeService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[PARTIALLY_PAID].freeze
      SUCCESS_STATUSES = %w[PAID].freeze
      FAILED_STATUSES = %w[EXPIRED CANCELLED].freeze

      def initialize(payable = nil)
        @payable = payable

        super
      end

      def call
        result.payable = payable
        return result unless should_process_payment?

        unless payable.total_amount_cents.positive?
          update_payable_payment_status(payment_status: :succeeded)
          return result
        end

        payable.increment_payment_attempts!

        payment = Payment.new(
          payable: payable,
          payment_provider_id: cashfree_payment_provider.id,
          payment_provider_customer_id: customer.cashfree_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency.upcase,
          provider_payment_id: payable.id, # NOTE: We are not creating a resource on cashfree's sude.
          status: :pending
        )
        payment.save!

        payable_payment_status = payable_payment_status(payment.status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      end

      def generate_payment_url
        return result unless should_process_payment?

        payment_link_response = create_payment_link(payment_url_params)
        result.payment_url = JSON.parse(payment_link_response.body)["link_url"]

        result
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)
        result.service_failure!(code: e.error_code, message: e.error_body)
      end

      def update_payment_status(organization_id:, status:, cashfree_payment:)
        payment = if cashfree_payment.metadata[:payment_type] == "one-time"
          create_payment(cashfree_payment)
        else
          Payment.find_by(provider_payment_id: cashfree_payment.id)
        end
        return result.not_found_failure!(resource: "cashfree_payment") unless payment

        result.payment = payment
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        payable_payment_status = payable_payment_status(status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)
        reset_customer_dunning_campaign_status(payable_payment_status)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def should_process_payment?
        return false if payable.payment_succeeded?
        return false if cashfree_payment_provider.blank?

        customer&.cashfree_customer&.id
      end

      def cashfree_payment_provider
        @cashfree_payment_provider ||= payment_provider(customer)
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
            lago_payable_id: payable.id,
            lago_payable_type: payable.class.name,
            payment_issuing_date: payable.created_at.iso8601,
            payment_type: "one-time"
          },
          link_id: "#{SecureRandom.uuid}.#{payable.payment_attempts}",
          link_amount: payable.total_amount_cents / 100.to_f,
          link_currency: payable.currency.upcase,
          link_purpose: payable.id,
          link_expiry_time: (Time.current + 10.minutes).iso8601,
          link_partial_payments: false,
          link_auto_reminders: false
        }
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
            ready_for_payment_processing: !payment_status_succeeded?(payment_status)
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
              ready_for_payment_processing: !payment_status_succeeded?(payment_status)
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def payment_status_succeeded?(payment_status)
        payment_status.to_sym == :succeeded
      end

      def create_payment(cashfree_payment)
        @payable = PaymentRequest.find(cashfree_payment.metadata[:lago_payable_id])

        payable.increment_payment_attempts!

        Payment.new(
          payable:,
          payment_provider_id: cashfree_payment_provider.id,
          payment_provider_customer_id: customer.cashfree_customer.id,
          amount_cents: payable.total_amount_cents,
          amount_currency: payable.currency.upcase,
          provider_payment_id: cashfree_payment.id
        )
      end

      def deliver_error_webhook(cashfree_error)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: customer.cashfree_customer.provider_customer_id,
          provider_error: {
            message: cashfree_error.error_body,
            error_code: cashfree_error.error_code
          }
        })
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status_succeeded?(payment_status)
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign!
      end
    end
  end
end
