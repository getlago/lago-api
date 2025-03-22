# frozen_string_literal: true

module Invoices
  class AdvanceChargesService < BaseService
    Result = BaseResult[:invoice]

    def initialize(initial_subscriptions:, billing_at:)
      @initial_subscriptions = initial_subscriptions
      @billing_at = billing_at

      @customer = initial_subscriptions&.first&.customer
      @organization = customer&.organization
      @currency = initial_subscriptions&.first&.plan&.amount_currency

      super
    end

    def call
      return result unless has_charges_with_statement?

      return result if subscriptions.empty?

      invoice = create_group_invoice

      if invoice && !invoice.closed?
        SendWebhookJob.perform_later("invoice.created", invoice)
        create_manual_payment(invoice)
        Invoices::GeneratePdfAndNotifyJob.perform_later(invoice:, email: false)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Utils::SegmentTrack.invoice_created(invoice)
      end

      result.invoice = invoice

      result
    end

    private

    attr_accessor :initial_subscriptions, :billing_at, :customer, :organization, :currency

    def subscriptions
      return [] unless organization

      # NOTE: filter all active/terminated subscriptions having non-invoiceable fees not yet attached to an invoice
      @subscriptions ||= organization.subscriptions
        .where(
          id: Fee.from_organization_pay_in_advance(organization)
            .where(payment_status: :succeeded)
            .where("succeeded_at <= ?", billing_at)
            .joins(:subscription)
            .where(subscriptions: {
              external_id: initial_subscriptions.pluck(:external_id).uniq,
              status: [:active, :terminated]
            })
            .select("DISTINCT(subscriptions.id)")
        )
    end

    def has_charges_with_statement?
      plan_ids = subscriptions.pluck(:plan_id)
      Charge.where(plan_id: plan_ids, pay_in_advance: true, invoiceable: false, regroup_paid_fees: :invoice).any?
    end

    def create_manual_payment(invoice)
      amount_cents = invoice.total_amount_cents
      reference = I18n.t("invoice.charges_paid_in_advance")
      created_at = invoice.created_at

      params = {invoice_id: invoice.id, amount_cents:, reference:, created_at:}

      ::Payments::ManualCreateJob.perform_later(organization:, params:)
    end

    def create_group_invoice
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = create_generating_invoice
        invoice.invoice_subscriptions.each do |is|
          is.subscription.fees
            .where(invoice: nil, payment_status: :succeeded)
            .where("succeeded_at <= ?", is.timestamp)
            .update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
        end

        if invoice.fees.empty?
          invoice = nil
          raise ActiveRecord::Rollback
        end

        # NOTE: We don't want to use Invoices::ComputeAmountsFromFees here
        #       because it would recompute taxes from pre-tax values. All Fees are already paid
        #       this invoice should show how much taxes were paid in total.
        Invoices::AggregateAmountsAndTaxesFromFees.call!(invoice:)

        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)

        invoice.payment_status = :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice:)

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
        Invoices::CreateAdvanceChargesInvoiceSubscriptionService.call!(
          invoice:,
          subscriptions_with_fees: subscriptions,
          all_subscriptions: subscriptions + initial_subscriptions,
          timestamp: billing_at
        )
      end

      invoice_result.raise_if_error!

      invoice_result.invoice
    end
  end
end
