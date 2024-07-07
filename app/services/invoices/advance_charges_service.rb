# frozen_string_literal: true

module Invoices
  class AdvanceChargesService < BaseService
    def initialize(subscriptions:, billing_at:)
      @subscriptions = subscriptions
      @billing_at = billing_at

      @customer = subscriptions&.first&.customer
      @organization = customer&.organization
      @currency = subscriptions&.first&.plan&.amount_currency

      super
    end

    def call
      return result unless has_charges_with_statement?

      return result if subscriptions.empty?

      invoice = create_group_invoice

      if invoice
        SendWebhookJob.perform_later('invoice.created', invoice)

        Invoices::GeneratePdfAndNotifyJob.perform_later(invoice:, email: false)

        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::SalesOrders::CreateJob.perform_later(invoice:) if invoice.should_sync_sales_order?
        Utils::SegmentTrack.invoice_created(invoice)
      end

      result.invoice = invoice

      result
    end

    private

    attr_accessor :subscriptions, :billing_at, :customer, :organization, :currency

    def has_charges_with_statement?
      plan_ids = subscriptions.pluck(:plan_id)
      Charge.where(plan_id: plan_ids, pay_in_advance: true, invoiceable: false, regroup_paid_fees: :invoice).any?
    end

    def create_group_invoice
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = create_generating_invoice
        invoice.invoice_subscriptions.each do |is|
          is.subscription.fees
            .where(invoice: nil, payment_status: :succeeded)
            .where("CAST(fees.properties->>'timestamp' AS timestamp) <= ?", is.charges_to_datetime)
            .update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
        end

        if invoice.fees.empty?
          invoice.invoice_subscriptions.destroy_all
          invoice.destroy!
          return nil
        end

        Invoices::ComputeAmountsFromFees.call(invoice:)

        invoice.payment_status = :succeeded
        invoice.status = :finalized

        invoice.save!
      end

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
