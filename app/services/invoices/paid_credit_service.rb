# frozen_string_literal: true

module Invoices
  class PaidCreditService < BaseService
    def initialize(wallet_transaction:, timestamp:, invoice: nil)
      @customer = wallet_transaction.wallet.customer
      @wallet_transaction = wallet_transaction
      @timestamp = timestamp

      # NOTE: In case of retry when the creation process failed,
      #       and if the generating invoice was persisted,
      #       the process can be retried without creating a new invoice
      @invoice = invoice

      super
    end

    def call
      create_generating_invoice unless invoice
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        create_credit_fee(invoice)
        compute_amounts(invoice)

        invoice.finalized!
      end

      track_invoice_created(result.invoice)
      SendWebhookJob.perform_later('invoice.paid_credit_added', result.invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice: result.invoice).finalized.deliver_later if should_deliver_email?
      Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
      Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?

      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :customer, :timestamp, :wallet_transaction, :invoice

    def currency
      @currency ||= wallet_transaction.wallet.currency
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :credit,
        currency:,
        datetime: Time.zone.at(timestamp),
      )
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :taxes_amount_cents)

      invoice.currency = currency
      invoice.fees_amount_cents = fee_amounts.sum(:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
      invoice.taxes_amount_cents = fee_amounts.sum(:taxes_amount_cents)
      invoice.sub_total_including_taxes_amount_cents = (
        invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents
      )
      invoice.total_amount_cents = invoice.sub_total_including_taxes_amount_cents
    end

    def create_credit_fee(invoice)
      fee_result = Fees::PaidCreditService
        .new(invoice:, wallet_transaction:, customer:).create

      fee_result.raise_if_error!
    end

    def should_deliver_webhook?
      customer.organization.webhook_endpoints.any?
    end

    def create_payment(invoice)
      Invoices::Payments::CreateService.new(invoice).call
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        },
      )
    end

    def should_deliver_email?
      License.premium? &&
        customer.organization.email_settings.include?('invoice.finalized')
    end
  end
end
