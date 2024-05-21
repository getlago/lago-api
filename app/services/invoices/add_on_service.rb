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
          payment_due_date:,
          net_payment_term: customer.applicable_net_payment_term,
          invoice_type: :add_on,
          payment_status: :pending,
          currency:,
          timezone: customer.applicable_timezone,
        )

        create_add_on_fee(invoice)
        compute_amounts(invoice)

        invoice.save!

        result.invoice = invoice
      end

      track_invoice_created(result.invoice)
      SendWebhookJob.perform_later('invoice.add_on_added', result.invoice) if should_deliver_webhook?
      InvoiceMailer.with(invoice: result.invoice).finalized.deliver_later if should_deliver_email?

      if result.invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice: result.invoice)
      end

      if result.invoice.should_sync_sales_order?
        Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice: result.invoice)
      end

      create_payment(result.invoice)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :datetime, :applied_add_on, :currency

    delegate :customer, to: :applied_add_on

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :taxes_amount_cents)

      invoice.fees_amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.sub_total_including_taxes_amount_cents = (
        invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents
      )
      invoice.total_amount_cents = invoice.sub_total_including_taxes_amount_cents
    end

    def create_add_on_fee(invoice)
      fee_result = Fees::AddOnService
        .new(invoice:, applied_add_on:).create
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

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      datetime.in_time_zone(customer.applicable_timezone).to_date
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end

    def should_deliver_email?
      License.premium? &&
        customer.organization.email_settings.include?('invoice.finalized')
    end
  end
end
