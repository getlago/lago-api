# frozen_string_literal: true

module Invoices
  module Payments
    class MoneyhashService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[processing].freeze
      SUCCESS_STATUSES = %w[succeeded].freeze
      FAILED_STATUSES = %w[failed].freeze

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

        payment = Payment.new(
          payable: invoice,
          payment_provider_id: moneyhash_payment_provider.id,
          payment_provider_customer_id: customer.moneyhash_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency.upcase,
          provider_payment_id: provider_payment_id,
          status: status
        )
        payment.save!

        invoice_payment_status = invoice_payment_status(payment.status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      end

      def update_payment_status(organization_id:, provider_payment_id:, status:, metadata: {})
        payment_obj = Payment.find_or_initialize_by(provider_payment_id: provider_payment_id)
        payment = if payment_obj.persisted?
          payment_obj
        else
          create_payment(provider_payment_id:, metadata:)
        end

        return handle_missing_payment(organization_id, metadata) unless payment
        result.payment = payment
        result.invoice = payment.payable
        return result if payment.payable.payment_succeeded?
        payment.update!(status:)
        update_invoice_payment_status(payment_status: invoice_payment_status(status), processing: status == "processing")
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      def generate_payment_url
        return result unless should_process_payment?
        response = client.post_with_response(payment_url_params, headers)
        moneyhash_result = JSON.parse(response.body)

        return result unless moneyhash_result

        moneyhash_result_data = moneyhash_result["data"]
        result.payment_url = moneyhash_result_data["embed_url"]
        result
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)
        result.service_failure!(code: e.error_code, message: e.message)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def handle_missing_payment(organization_id, metadata)
        return result unless metadata&.key?("lago_payable_id")
        invoice = Invoice.find_by(id: metadata["lago_payable_id"], organization_id:)
        return result if invoice.nil?

        return result if invoice.payment_failed?

        result.not_found_failure!(resource: "moneyhash_payment")
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result = Invoices::UpdateService.call(
          invoice: invoice.presence || @result.invoice,
          params: {
            payment_status:,
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def create_payment(provider_payment_id:, metadata:)
        @invoice = Invoice.find_by(id: metadata["lago_payable_id"])
        unless @invoice
          result.not_found_failure!(resource: "invoice")
          return
        end
        increment_payment_attempts
        Payment.new(
          payable: invoice,
          payment_provider_id: moneyhash_payment_provider.id,
          payment_provider_customer_id: customer.moneyhash_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency&.upcase,
          provider_payment_id:
        )
      end

      def should_process_payment?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if moneyhash_payment_provider.blank?

        customer&.moneyhash_customer&.provider_customer_id
      end

      def client
        @client || LagoHttpClient::Client.new("#{::PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/")
      end

      def headers
        {
          "Content-Type" => "application/json",
          "x-Api-Key" => moneyhash_payment_provider.api_key
        }
      end

      def moneyhash_payment_provider
        @moneyhash_payment_provider ||= payment_provider(customer)
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def payment_url_params
        params = {
          amount: invoice.total_amount_cents / 100.0,
          amount_currency: invoice.currency.upcase,
          flow_id: moneyhash_payment_provider.flow_id,
          billing_data: {
            first_name: invoice&.customer&.firstname,
            last_name: invoice&.customer&.lastname,
            phone_number: invoice&.customer&.phone,
            email: invoice&.customer&.email
          },
          customer: invoice.customer.moneyhash_customer.provider_customer_id,
          webhook_url: moneyhash_payment_provider.webhook_end_point,
          merchant_initiated: false,
          tokenize_card: true,
          custom_fields: {
            lago_mit: false,
            lago_customer_id: invoice&.customer&.id,
            lago_payable_id: invoice.id,
            lago_payable_type: invoice.class.name,
            lago_organization_id: organization&.id,
            lago_mh_service: "Invoices::Payments::MoneyhashService"
          }
        }
        # Include recurring data for subscription invoices only
        if invoice.invoice_type == "subscription"
          params[:recurring_data] = {
            agreement_id: invoice.subscriptions&.first&.external_id
          }
          params[:payment_type] = "UNSCHEDULED"
          params[:custom_fields].merge!(
            lago_plan_id: invoice.subscriptions&.first&.plan_id,
            lago_subscription_external_id: invoice.subscriptions&.first&.external_id
          )
        end
        params
      end

      def deliver_error_webhook(moneyhash_error)
        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: customer.moneyhash_customer.provider_customer_id,
          provider_error: {
            message: moneyhash_error.message,
            error_code: moneyhash_error.error_code
          }
        })
      end
    end
  end
end
