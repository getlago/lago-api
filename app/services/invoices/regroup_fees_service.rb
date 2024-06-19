# frozen_string_literal: true

module Invoices
  class RegroupFeesService < BaseService
    def initialize(subscriptions:, billing_at:)
      @subscriptions = subscriptions
      @billing_at = billing_at

      @customer = subscriptions&.first&.customer
      @organization = customer&.organization
      @currency = subscriptions&.first&.plan&.amount_currency

      super
    end

    def call
      # TODO: Implement organization settings if we choose the org setting approach
      # return result unless organization&.advance_charges_invoice?

      return result if subscriptions.empty?

      invoices = []

      ActiveRecord::Base.transaction do
        invoices << create_group_invoice(fees_payment_status: :succeeded, invoice_payment_status: :succeeded)
        invoices << create_group_invoice(fees_payment_status: [:pending, :failed], invoice_payment_status: :pending)
      end

      result.invoices = invoices.compact

      result.invoices.each do |i|
        SendWebhookJob.perform_later('invoice.created', i)

        Invoices::GeneratePdfAndNotifyJob.perform_later(invoice: i, email: false)

        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice: i) if i.should_sync_invoice?
        Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice: i) if i.should_sync_sales_order?
        Utils::SegmentTrack.invoice_created(i)

        if i.payment_status == "pending"
          Invoices::Payments::CreateService.call(i)
        end
      end

      result
    end

    private

    attr_accessor :subscriptions, :billing_at, :customer, :organization, :currency

    def create_group_invoice(fees_payment_status:, invoice_payment_status:)
      invoice = create_generating_invoice
      invoice.invoice_subscriptions.each do |is|
        is.subscription.fees
          .where(invoice: nil, payment_status: fees_payment_status)
          .where("CAST(fees.properties->>'timestamp' AS timestamp) <= ?", is.charges_to_datetime)
          # TODO: Note that payment_status cannot be nil! should we keep it in pending?
          .update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
      end

      if invoice.fees.empty?
        invoice.invoice_subscriptions.destroy_all
        invoice.destroy!
        return nil
      end

      Invoices::ComputeAmountsFromFees.call(invoice:)

      invoice.payment_status = invoice_payment_status
      invoice.status = :finalized

      invoice.save!

      invoice
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :advance_charges,
        currency:,
        datetime: billing_at, # this is an int we need to convert it
        skip_charges: true
      ) do |invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions:, timestamp: billing_at.to_i, invoicing_reason: :in_advance_charge_periodic)
          .raise_if_error!
      end

      invoice_result.raise_if_error!

      invoice_result.invoice
    end
  end
end
