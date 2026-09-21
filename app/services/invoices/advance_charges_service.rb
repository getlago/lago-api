# frozen_string_literal: true

module Invoices
  class AdvanceChargesService < BaseService
    Result = BaseResult[:invoice]

    def initialize(billing_contexts:, billing_at:)
      @billing_contexts = billing_contexts
      @billing_at = billing_at

      @customer = billing_contexts&.first&.customer
      @currency = billing_contexts&.first&.currency

      super
    end

    def call
      return result if pending_billing_contexts_with_fees.empty?

      invoices = create_group_invoices

      invoices.each do |invoice|
        next if invoice.closed?

        SendWebhookJob.perform_later("invoice.created", invoice)
        Utils::ActivityLog.produce(invoice, "invoice.created")
        create_manual_payment(invoice)
        Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: false)
        Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
        Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
        Utils::SegmentTrack.invoice_created(invoice)
      end

      result.invoice = invoices.last

      result
    end

    private

    attr_reader :billing_contexts, :billing_at, :customer, :currency

    # Apply the charges_to_datetime upper-bound only for regular periodic billing
    # (i.e., no upgrade/downgrade/termination context). We consider it regular when
    # every source subscription is active AND has no pending next subscription AND
    # is not being terminated.
    def apply_charges_to_datetime_condition?
      billing_contexts.all? do |billing_context|
        billing_context.active? && billing_context.next_subscription.nil? && !billing_context.terminated?
      end
    end

    def filter_charges_to_datetime(relation)
      return relation unless apply_charges_to_datetime_condition?

      relation.where("(properties ->> 'charges_to_datetime') IS NULL OR (properties ->> 'charges_to_datetime')::timestamp <= ?", billing_at)
    end

    def pending_billing_contexts_with_fees
      return [] unless customer

      # NOTE: filter all active/terminated subscriptions having non-invoiceable (in advance) fees not yet attached to an invoice
      @pending_billing_contexts_with_fees ||= customer.subscriptions
        .where(
          id: Fee.joins(:subscription)
            .where(invoice_id: nil, payment_status: :succeeded)
            .where("succeeded_at <= ?", billing_at)
            .then { |rel| filter_charges_to_datetime(rel) }
            .where(subscriptions: {
              customer_id: customer.id,
              external_id: billing_contexts.map(&:external_id).uniq,
              status: [:active, :terminated]
            })
            .select("DISTINCT(subscriptions.id)")
        )
        .map { |subscription| Billing::Context.from(subscription:) }
    end

    def create_manual_payment(invoice)
      params = {
        invoice_id: invoice.id,
        amount_cents: invoice.total_amount_cents,
        reference: I18n.t("invoice.charges_paid_in_advance"),
        created_at: invoice.created_at
      }

      ::Payments::ManualCreateJob.perform_later(organization: invoice.organization, params:)
    end

    # NOTE: The re-expanded subscription set (matched by external_id) can span several
    #       purchase order numbers — e.g. a terminated and an active subscription sharing
    #       an external_id after an upgrade. Each PO must produce its own invoice.
    def create_group_invoices
      pending_billing_contexts_with_fees.group_by(&:purchase_order_number).values.filter_map do |billing_contexts_group|
        create_group_invoice(billing_contexts_group)
      end
    end

    def create_group_invoice(billing_contexts_group)
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = create_generating_invoice(billing_contexts_group)
        Fees::AdvanceChargesService.call!(invoice:, billing_contexts: billing_contexts_group, billing_at:)

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

    def create_generating_invoice(billing_contexts_group)
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :advance_charges,
        currency:,
        datetime: billing_at, # this is an int we need to convert it
        billing_entity: billing_contexts.first&.billing_entity || customer.billing_entity,
        purchase_order_number: billing_contexts_group.first&.purchase_order_number
      ) do |invoice|
        Invoices::CreateAdvanceChargesInvoiceService.call!(
          invoice:,
          billing_contexts_with_fees: billing_contexts_group,
          all_billing_contexts: (billing_contexts_group + billing_contexts).uniq(&:subscription_id),
          timestamp: billing_at
        )
      end

      invoice_result.raise_if_error!

      invoice_result.invoice
    end
  end
end
