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
      BillingSegment.status_pending
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
      grouped = segments.group_by { |s| s.contract_rate_card.product.product_type }
      metered_segments = grouped[Product::PRODUCT_TYPES[:metered]] || []
      fixed_segments = grouped[Product::PRODUCT_TYPES[:fixed]] || []

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

        filtered_aggregations = event_filters(metered_segments)

        attach_fixed_fees(fixed_segments, invoice)
        attach_metered_fees(metered_segments, invoice, filtered_aggregations)

        invoice.fees.reload

        Invoices::ComputeAmountsFromFees.call!(invoice:)
        invoice.save!
        segments.each { |segment| segment.update!(status: :done, invoice:) }
      end

      invoice
    end

    def attach_fixed_fees(segments, invoice)
      segments.each do |segment|
        compute_fixed_fees(segment).each do |fee|
          fee.invoice = invoice
          fee.billing_entity = invoice.billing_entity
          fee.save!
        end
      end
    end

    def attach_metered_fees(segments, invoice, filtered_aggregations)
      segments.each do |segment|
        compute_metered_fees(segment, invoice, filtered_aggregations)
      end
    end

    def compute_fixed_fees(segment)
      fee_result = BillingSegments::Fees::ComputeService.call!(billing_segment: segment)
      [fee_result.fee, fee_result.true_up_fee].compact
    end

    # NOTE: Fees::ChargeService persists and attaches the product fees itself (within this
    # surrounding transaction), so a failure on any segment rolls back the whole invoice group.
    def compute_metered_fees(segment, invoice, filtered_aggregations)
      ::Fees::ChargeService.call!(
        invoice:,
        metered_item: ::Fees::ChargeService::MeteredItem.from_billing_segment(segment),
        billing_context: Billing::Context.from(contract: segment.contract),
        options: ::Fees::ChargeService::Options.new(context: :finalize, skip_adjusted_fees: true),
        filtered_aggregations: filtered_aggregations[segment.target_key]&.keys || []
      )
    end

    def event_filters(metered_segments)
      return {} if metered_segments.empty?

      Events::BillingPeriodFilterService.for_billing_segments!(
        billing_segments: metered_segments, with_last_seen_at: false
      ).filter_targets
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
