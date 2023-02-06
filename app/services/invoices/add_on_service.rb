# frozen_string_literal: true

module Invoices
  class AddOnService < BaseService
    def initialize(applied_add_on:, datetime:)
      @applied_add_on = applied_add_on
      @datetime = datetime
      @currency = applied_add_on.amount_currency

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          organization: customer.organization,
          customer:,
          issuing_date:,
          invoice_type: :add_on,
          payment_status: :pending,
          amount_currency: currency,
          vat_amount_currency: currency,
          credit_amount_currency: currency,
          total_amount_currency: currency,
          vat_rate: customer.applicable_vat_rate,
          timezone: customer.applicable_timezone,
        )

        create_add_on_fee(invoice)

        compute_amounts(invoice)

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.save!

        track_invoice_created(invoice)
        result.invoice = invoice
      end

      SendWebhookJob.perform_later(:add_on, result.invoice) if should_deliver_webhook?
      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :datetime, :applied_add_on, :currency

    delegate :customer, to: :applied_add_on

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = applied_add_on.amount_currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = applied_add_on.amount_currency
    end

    def create_add_on_fee(invoice)
      fee_result = Fees::AddOnService
        .new(invoice:, applied_add_on:).create
      fee_result.raise_if_error!
    end

    def should_deliver_webhook?
      customer.organization.webhook_url?
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

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      datetime.in_time_zone(customer.applicable_timezone).to_date
    end
  end
end
