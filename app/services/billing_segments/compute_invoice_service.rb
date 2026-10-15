# frozen_string_literal: true

module BillingSegments
  class ComputeInvoiceService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, billing_segments:, context:)
      @invoice = invoice
      @billing_segments = billing_segments
      @context = context
      super
    end

    def call
      grouped = billing_segments.group_by { |segment| segment.contract_rate_card.product.product_type }
      metered_segments = grouped[Product::PRODUCT_TYPES[:metered]] || []
      fixed_segments = grouped[Product::PRODUCT_TYPES[:fixed]] || []
      filtered_aggregations = event_filters(metered_segments)

      attach_fixed_fees(fixed_segments)
      attach_metered_fees(metered_segments, filtered_aggregations)

      invoice.fees.reload
      Invoices::ComputeAmountsFromFees.call!(invoice:)
      invoice.save!

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :billing_segments, :context

    def attach_fixed_fees(segments)
      segments.each do |segment|
        compute_fixed_fees(segment).each do |fee|
          fee.invoice = invoice
          fee.billing_entity = invoice.billing_entity
          fee.save!
        end
      end
    end

    def attach_metered_fees(segments, filtered_aggregations)
      segments.each do |segment|
        compute_metered_fees(segment, filtered_aggregations)
      end
    end

    def compute_fixed_fees(segment)
      fee_result = BillingSegments::Fees::ComputeService.call!(billing_segment: segment)
      [fee_result.fee, fee_result.true_up_fee].compact
    end

    def compute_metered_fees(segment, filtered_aggregations)
      ::Fees::ChargeService.call!(
        invoice:,
        metered_item: ::Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment),
        billing_context: Billing::Context.from(contract: segment.contract),
        options: ::Fees::ChargeService::Options.new(context:, skip_adjusted_fees: true),
        filtered_aggregations: filtered_aggregations[segment.target_key]&.keys || []
      )
    end

    def event_filters(metered_segments)
      return {} if metered_segments.empty?

      Events::BillingPeriodFilterService.for_billing_segments!(
        billing_segments: metered_segments, with_last_seen_at: false
      ).filter_targets
    end
  end
end
