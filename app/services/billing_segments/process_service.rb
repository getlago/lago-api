# frozen_string_literal: true

module BillingSegments
  class ProcessService < BaseService
    Result = BaseResult[:invoices]

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      result.invoices = []

      acquired = customer.with_advisory_lock("billing_segment_process_customer_#{customer.id}", timeout_seconds: 0) do
        segments = pending_segments
        segments.group_by { |segment| invoice_key(segment) }.each_value do |invoice_segments|
          result.invoices << build_invoice(invoice_segments)
        end

        finalize_generating_invoices
        true
      end

      unless acquired
        raise BaseLockService::FailedToAcquireLock, "Failed to acquire billing segment lock for customer #{customer.id}"
      end

      result
    end

    private

    attr_reader :customer

    def pending_segments
      BillingSegment.awaiting_invoicing
        .where(customer_id: customer.id)
        .includes(:pricing_unit, :rate_override, :contract, contract_rate_card: {rate_card: :product}, rate_card_rate: :rate_card)
    end

    def invoice_key(segment)
      contract = segment.contract
      [
        segment.billing_at.in_time_zone(customer.applicable_timezone).to_date,
        contract.consolidate_invoice ? :shared : segment.id,
        segment.currency,
        contract.billing_entity_id || customer.billing_entity_id,
        payment_method_key(contract),
        contract.purchase_order_number
      ]
    end

    def payment_method_key(contract)
      if contract.payment_method_id.present?
        [contract.payment_method_id, contract.payment_method_type]
      elsif contract.payment_method_type == "manual"
        [nil, "manual"]
      elsif customer.default_payment_method.present?
        [customer.default_payment_method.id, "provider"]
      else
        [nil, contract.payment_method_type]
      end
    end

    def build_invoice(segments)
      contract = segments.first.contract
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = Invoices::CreateGeneratingService.call!(
          customer:,
          billing_entity: contract.billing_entity || customer.billing_entity,
          invoice_type: :subscription,
          invoicing_reason: :subscription_periodic,
          currency: segments.first.currency,
          datetime: segments.first.billing_at,
          purchase_order_number: contract.purchase_order_number
        ).invoice

        context = grace_period?(invoice) ? :draft : :finalize
        BillingSegments::ComputeInvoiceService.call!(
          invoice:,
          billing_segments: segments,
          context:
        )
        segments.each { |segment| segment.update!(status: :done, invoice:) }

        if context == :draft
          invoice.update!(status: :draft)
          notify_draft_created(invoice)
        end
      end

      invoice
    end

    def grace_period?(invoice)
      customer.applicable_invoice_grace_period(billing_entity: invoice.billing_entity).positive?
    end

    def notify_draft_created(invoice)
      customer.flag_wallets_for_refresh
      SendWebhookJob.perform_after_commit("invoice.drafted", invoice)
      Utils::ActivityLog.produce_after_commit(invoice, "invoice.drafted")

      return if invoice.tax_pending?

      SendWebhookJob.perform_after_commit("invoice.ready_to_finalize", invoice)
      Utils::ActivityLog.produce_after_commit(invoice, "invoice.ready_to_finalize")
    end

    def finalize_generating_invoices
      # Re-query done segments so a retry finalizes existing invoices without rebuilding fees.
      invoice_ids = BillingSegment.status_done
        .where(customer_id: customer.id)
        .joins(:invoice)
        .where(invoices: {status: :generating})
        .select(:invoice_id)

      Invoice.where(id: invoice_ids).find_each do |invoice|
        Invoices::TransitionToFinalStatusService.call!(invoice:)
        invoice.save! if invoice.changed?
      end
    end
  end
end
