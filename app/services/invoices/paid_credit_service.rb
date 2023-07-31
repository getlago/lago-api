# frozen_string_literal: true

module Invoices
  class PaidCreditService < BaseService
    def initialize(wallet_transaction:, timestamp:)
      @customer = wallet_transaction.wallet.customer
      @wallet_transaction = wallet_transaction
      @timestamp = timestamp

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          organization: customer.organization,
          customer:,
          issuing_date:,
          payment_due_date: issuing_date,
          net_payment_term: customer.applicable_net_payment_term,
          invoice_type: :credit,
          payment_status: :pending,
          currency:,

          # NOTE: No VAT should be applied on as it can be considered as an advance
          taxes_rate: 0,
          timezone: customer.applicable_timezone,
        )

        create_credit_fee(invoice)
        compute_amounts(invoice)

        invoice.save!

        result.invoice = invoice
      end

      track_invoice_created(result.invoice)
      SendWebhookJob.perform_later('invoice.paid_credit_added', result.invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice: result.invoice).finalized.deliver_later if should_deliver_email?

      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :customer, :timestamp, :wallet_transaction

    def currency
      @currency ||= wallet_transaction.wallet.currency
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
          invoice_type: invoice.invoice_type,
        },
      )
    end

    def issuing_date
      Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    end

    def should_deliver_email?
      License.premium? &&
        customer.organization.email_settings.include?('invoice.finalized')
    end
  end
end
