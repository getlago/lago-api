# frozen_string_literal: true

module Invoices
  class PaidCreditService < BaseService
    def initialize(customer:, wallet_transaction:, date:)
      @customer = customer
      @wallet_transaction = wallet_transaction
      @date = date

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          customer: customer,
          issuing_date: date,
          invoice_type: :credit,
          status: :pending,
        )

        create_credit_fee(invoice)

        compute_amounts(invoice)

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.total_amount_currency = currency
        invoice.save!

        track_invoice_created(invoice)
        result.invoice = invoice
      end

      SendWebhookJob.perform_later(:credit, result.invoice) if should_deliver_webhook?
      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :customer, :date, :wallet_transaction

    def currency
      @currency ||= customer.default_currency
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = currency
    end

    def create_credit_fee(invoice)
      fee_result = Fees::PaidCreditService
        .new(invoice: invoice, wallet_transaction: wallet_transaction, customer: customer).create

      raise fee_result.throw_error unless fee_result.success?
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
    end

    def create_payment(invoice)
      case customer.payment_provider&.to_sym
      when :stripe
        Invoices::Payments::StripeCreateJob.perform_later(invoice)
      end
    end

    def track_invoice_created(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end
  end
end
