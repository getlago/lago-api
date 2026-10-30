# frozen_string_literal: true

module BillingSegments
  module Fees
    # The day-by-day changes behind the units of a recurring product fee billed in arrears, as
    # Invoice#recurring_breakdown lists them for a charge fee, read from the fee's billing segment.
    class RecurringBreakdownService < BaseService
      Result = BaseResult[:breakdown]

      BREAKDOWN_SERVICES = {
        "sum_agg" => BillableMetrics::Breakdown::SumService,
        "unique_count_agg" => BillableMetrics::Breakdown::UniqueCountService
      }.freeze

      def initialize(fee:)
        @fee = fee
        super
      end

      def call
        breakdown_service = BREAKDOWN_SERVICES[fee.invoiceable.billable_metric&.aggregation_type]
        return result.not_allowed_failure!(code: "unsupported_aggregation_type") unless breakdown_service
        return result.not_found_failure!(resource: "billing_segment") unless billing_segment

        result.breakdown = breakdown_service.new(
          event_store: provider.store_for(metered_item:, boundaries:, filters:),
          metered_item:,
          billing_context:,
          boundaries:,
          filters:
        ).breakdown.breakdown
        result
      end

      private

      attr_reader :fee

      # Fees store their segment's bounds, and a rate card has one segment starting at a given time.
      def billing_segment
        @billing_segment ||= BillingSegment.find_by(
          organization_id: fee.organization_id,
          contract_rate_card_id: fee.contract_rate_card_id,
          started_at: boundaries[:from_datetime]
        )
      end

      def boundaries
        @boundaries ||= {
          from_datetime: Time.zone.parse(fee.properties["charges_from_datetime"]),
          to_datetime: Time.zone.parse(fee.properties["charges_to_datetime"]),
          charges_duration: fee.properties["charges_duration"]
        }
      end

      def metered_item
        @metered_item ||= ::Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, product_filter: fee.product_filter)
      end

      # The product filters scope the events as they did when the fee was billed (Fees::ChargeService).
      def filters
        @filters ||= begin
          matching_and_ignored_filters = metered_item.matching_and_ignored_filters
          {matching_filters: matching_and_ignored_filters.matching_filters, ignored_filters: matching_and_ignored_filters.ignored_filters}
        end
      end

      def billing_context
        @billing_context ||= Billing::Context.from(contract: billing_segment.contract)
      end

      def provider
        Events::Stores::Provider.new(organization: billing_segment.organization, billing_context:)
      end
    end
  end
end
