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
        invoice = Invoice.find_or_create_by!(
          subscription: subscription,
          from_date: nil,
          to_date: nil,
          issuing_date: date,
        )

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
      vat_rate = applied_add_on.customer.organization.vat_rate

      invoice.amount_cents = applied_add_on.amount_cents
      invoice.amount_currency = plan.amount_currency
      invoice.vat_amount_cents = (applied_add_on.amount_cents * vat_rate).fdiv(100).ceil
      invoice.vat_amount_currency = plan.amount_currency
    end

    def should_deliver_webhook?
      subscription.organization.webhook_url?
    end
  end
end
