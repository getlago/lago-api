# frozen_string_literal: true

module BillingSegments
  class BuildCurrentUsageService < BaseService
    Result = BaseResult[:billing_segments, :boundaries]

    def initialize(billing_context:, timestamp:, usage_filters: UsageFilters::NONE)
      @billing_context = billing_context
      @timestamp = timestamp
      @usage_filters = usage_filters
      super
    end

    # NOTE: This service is not production ready, it's just for testing proposes. It will be refactored and improved in the near future.
    def call
      result.billing_segments = []
      windows = []

      applied_rate_cards.each do |card|
        card.association(:contract).target = contract
        schedule_result = Billing::RateCards::BuildScheduleService.call(contract_rate_card: card)
        unless schedule_result.success?
          return result.fail_with_error!(schedule_result.error)
        end
        schedule = schedule_result.schedule
        slices = schedule.segments_in_cycle_at(timestamp)
        windows.concat(slices)

        slices.each do |slice|
          next if slice.started_at > timestamp

          segment = build_segment(card, slice)
          segment.association(:contract_rate_card).target = card
          segment.association(:contract).target = contract
          segment.association(:customer).target = customer
          result.billing_segments << segment
        end
      end

      if result.billing_segments.any? { |segment| segment.currency != billing_context.currency }
        return result.not_allowed_failure!(code: "usage_currency_mismatch")
      end

      from = windows.map(&:cycle_started_at).min || timestamp.in_time_zone(timezone).beginning_of_day
      to = windows.map(&:ended_at).max || from.next_day
      result.boundaries = BillingPeriodBoundaries.new(
        from_datetime: from,
        to_datetime: BillingSegment.inclusive_end(to),
        charges_from_datetime: from,
        charges_to_datetime: BillingSegment.inclusive_end(to),
        charges_duration: Billing::Days.between(from, to, timezone:),
        issuing_date: BillingSegment.inclusive_end(to).in_time_zone(timezone).to_date,
        timestamp:
      )
      result
    end

    private

    attr_reader :billing_context, :timestamp, :usage_filters

    delegate :contract, :customer, :organization, to: :billing_context

    def timezone
      customer.applicable_timezone
    end

    def applied_rate_cards
      date = timestamp.in_time_zone(timezone).to_date
      cards = contract.applied_rate_cards
        .strict_loading
        .where(effective_date: ..date)
        .where("ended_date IS NULL OR ended_date >= ?", date)
        .joins(rate_card: :product)
        .where(products: {product_type: :usage})
        .includes(:contract, rate_phases: :rate_override,
          product: {billable_metric: :organization, filters: {values: :billable_metric_filter}},
          rate_card: [:rates, {product: {billable_metric: :organization, filters: {values: :billable_metric_filter}}}])

      if usage_filters.filter_by_product_id.present?
        cards = cards.where(products: {id: usage_filters.filter_by_product_id})
      elsif usage_filters.filter_by_product_code.present?
        cards = cards.where(products: {code: usage_filters.filter_by_product_code})
      end

      if usage_filters.filter_by_metric_code.present?
        cards = cards.joins(rate_card: {product: :billable_metric})
          .where(billable_metrics: {code: usage_filters.filter_by_metric_code})
      end
      cards
    end

    def build_segment(card, slice)
      BillingSegment.new(
        organization:, customer:, contract:, contract_rate_card: card,
        rate_card_rate: slice.rate, rate_override: slice.rate_override,
        currency: card.rate_card.currency,
        pricing_unit: pricing_units[card.rate_card.applied_pricing_unit_code],
        rate_properties: (slice.rate_override || slice.rate).rate_properties,
        cycle_started_at: slice.cycle_started_at,
        started_at: slice.started_at, ended_at: BillingSegment.inclusive_end(slice.ended_at),
        billing_at: slice.billing_at, proration_ratio: slice.proration_ratio
      )
    end

    def pricing_units
      @pricing_units ||= organization.pricing_units.strict_loading.index_by(&:code)
    end
  end
end
