# frozen_string_literal: true

module BillingSegments
  class ProcessService < BaseService
    Result = BaseResult[:invoices]

    def initialize(customer:, timestamp: Time.current)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.invoices = []

      acquired = customer.with_advisory_lock("billing_segment_process_customer_#{customer.id}", timeout_seconds: 0) do
        pending_segments.group_by { |segment| pending_invoice_key(segment) }.each_value do |invoice_segments|
          invoice = build_invoice(invoice_segments)
          result.invoices << invoice if invoice
        end

        pending_advance_segments.group_by { |segment| invoice_key(segment) }.each_value do |invoice_segments|
          invoice = process_pending_advance_segments(invoice_segments)
          result.invoices << invoice if invoice
        end

        finalize_generating_invoices
        result.invoices.each(&:reload)
        true
      end

      unless acquired
        raise BaseLockService::FailedToAcquireLock, "Failed to acquire billing segment lock for customer #{customer.id}"
      end

      result
    end

    private

    attr_reader :customer, :timestamp

    def pending_segments
      grouped_segments.fetch(:pending_segments, [])
    end

    def pending_advance_segments
      grouped_segments.fetch(:pending_advance_segments, [])
    end

    def grouped_segments
      @grouped_segments ||= BillingSegment.ready_for_invoicing(timestamp)
        .where(customer_id: customer.id)
        .includes(:pricing_unit, :rate_override, :contract, :rate_card_rate,
          contract_rate_card: {rate_card: {product: :billable_metric}})
        .sort_by { |segment| [segment.billing_at, segment.id] }
        .filter_map do |segment|
          group = segment_group(segment)
          [group, segment] if group
        end
        .group_by(&:first)
        .transform_values { |grouped_segments| grouped_segments.map(&:last) }
    end

    def segment_group(segment)
      advance_metered = segment.contract_rate_card.rate_card.advance? && segment.contract_rate_card.product.metered?

      if advance_metered && !segment.recurring_advance_invoiceable?
        :pending_advance_segments
      elsif segment.status_pending?
        :pending_segments
      end
    end

    def pending_invoice_key(segment)
      invoice_key(segment, billing_at: segment.billing_at)
    end

    def invoice_key(segment, billing_at: segment.cycle_started_at)
      contract = segment.contract
      [
        billing_at.in_time_zone(customer.applicable_timezone).to_date,
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
        ActiveRecord::Base.transaction(requires_new: true) do
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
          Invoices::ApplyInvoiceCustomSectionsService.call!(
            invoice:,
            resources: segments.map(&:contract).uniq.map { |segment_contract| Invoices::ApplyInvoiceCustomSectionsService::Resource.from(resource: segment_contract) }
          )
          if context == :draft
            invoice.update!(status: :draft)
            notify_draft_created(invoice)
          end

          if context == :finalize && segments.all?(&:recurring_advance_invoiceable?) && invoice.fees.reload.empty?
            invoice = nil
            raise ActiveRecord::Rollback
          end
        end

        segments.each { |segment| segment.update!(status: :done, invoice:) }
      end

      invoice
    end

    def process_pending_advance_segments(segments)
      metered_items = segments.map do |segment|
        ::Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment)
      end
      billing_contexts = segments.map do |segment|
        Billing::Context.from(contract: segment.contract)
      end
      invoice = nil
      fee_result = nil

      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction(requires_new: true) do
          invoice = create_advance_invoice(segments)
          fee_result = ::Fees::AdvanceChargesService.call!(
            invoice:,
            billing_contexts:,
            metered_items:,
            billing_at: segments.first.billing_at
          )

          if invoice.fees.reload.empty?
            invoice = nil
            raise ActiveRecord::Rollback
          end

          Invoices::AggregateAmountsAndTaxesFromFees.call!(invoice:)
          Invoices::ApplyInvoiceCustomSectionsService.call!(
            invoice:,
            resources: segments.map(&:contract).uniq.map { |contract| Invoices::ApplyInvoiceCustomSectionsService::Resource.from(resource: contract) }
          )
          invoice.payment_status = :succeeded
          invoice.save!
        end

        invoiced_segment_ids = fee_result&.invoiced_metered_items&.map { |item| item.billing_segment.id }&.to_set || Set.new

        segments.each do |segment|
          segment_invoice = invoice if invoiced_segment_ids.include?(segment.id)
          segment.update!(status: :done, invoice: segment_invoice)
        end
      end

      invoice
    end

    def create_advance_invoice(segments)
      contract = segments.first.contract

      Invoices::CreateGeneratingService.call!(
        customer:,
        invoice_type: :advance_charges,
        currency: segments.first.currency,
        datetime: segments.first.billing_at,
        skip_charges: true,
        billing_entity: contract.applicable_billing_entity,
        purchase_order_number: contract.purchase_order_number
      ).invoice
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

      Invoice.where(id: invoice_ids).order(:issuing_date, :id).each do |invoice|
        if invoice.advance_charges?
          Invoices::FinalizeAndPublishAdvanceChargesService.call!(invoice:)
        else
          Invoices::TransitionToFinalStatusService.call!(invoice:)
          invoice.save! if invoice.changed?
        end
      end
    end
  end
end
