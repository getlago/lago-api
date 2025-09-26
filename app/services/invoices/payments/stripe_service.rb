# frozen_string_literal: true

module Invoices
  module Payments
    class StripeService < BaseService
      include Customers::PaymentProviderFinder

      PROVIDER_NAME = "Stripe"

      def initialize(invoice = nil)
        @invoice = invoice

        super
      end

      def update_payment_status(organization_id:, status:, stripe_payment:)
        payment = Payment.find_by(provider_payment_id: stripe_payment.id)
        return result if payment&.payable&.organization_id.present? && payment.payable.organization_id != organization_id

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
      rescue ActiveRecord::RecordNotUnique
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
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
          organization: @invoice.organization,
          payable: @invoice,
          customer:,
          payment_provider_id: stripe_payment_provider.id,
          payment_provider_customer_id: customer.stripe_customer.id,
          amount_cents: @invoice.total_due_amount_cents,
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

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        params = {
          payment_status:,
          # NOTE: A proper `processing` payment status should be introduced for invoices
          ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded
        }

        if payment_status.to_sym == :succeeded
          total_paid_amount_cents = (invoice.presence || @result.invoice).payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
          params[:total_paid_amount_cents] = total_paid_amount_cents
        end

        result = Invoices::UpdateService.call(
          invoice: invoice.presence || @result.invoice,
          params:,
          webhook_notification: deliver_webhook
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
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

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
