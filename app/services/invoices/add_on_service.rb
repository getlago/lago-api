# frozen_string_literal: true

module Invoices
  class AddOnService < BaseService
    def initialize(subscription:, applied_add_on:, date:)
      @subscription = subscription
      @applied_add_on = applied_add_on
      @date = date

      super(nil)
    end

    def create
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          subscription: subscription,
          from_date: date,
          to_date: date,
          issuing_date: date,
          invoice_type: :add_on,
        )

        create_add_on_fee(invoice)

        compute_amounts(invoice)

        invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
        invoice.total_amount_currency = plan.amount_currency
        invoice.save!

        result.invoice = invoice
      end

      SendWebhookJob.perform_later(:add_on, result.invoice) if should_deliver_webhook?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :subscription, :date, :applied_add_on

    delegate :plan, to: :subscription

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = plan.amount_currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = plan.amount_currency
    end

    def create_add_on_fee(invoice)
      fee_result = Fees::AddOnService.new(invoice: invoice, applied_add_on: applied_add_on).create
      raise fee_result.throw_error unless fee_result.success?
    end

    def should_deliver_webhook?
      subscription.organization.webhook_url?
    end
  end
end
