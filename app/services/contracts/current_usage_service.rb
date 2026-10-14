# frozen_string_literal: true

module Contracts
  # Prices, for each card effective at the timestamp, the billing window open at that instant,
  # through the code that invoices it.
  class CurrentUsageService < BaseService
    Filters = BaseFilters[:rate_card_code, :product_code, :product_filter_code, :product_type]

    Result = BaseResult[:rate_card_usages, :amount_cents, :taxes_amount_cents, :total_amount_cents]

    def initialize(contract:, timestamp: Time.current, apply_taxes: true, filters: {})
      @contract = contract
      @timestamp = timestamp
      @apply_taxes = apply_taxes
      @filters = Filters.new(**(filters || {}))
      super
    end

    def call
      if filters[:product_type].present? && !Product::PRODUCT_TYPES.value?(filters[:product_type])
        return result.single_validation_failure!(field: :product_type, error_code: "value_is_invalid")
      end

      # A pending contract has not started billing, so it has no usage yet.
      result.rate_card_usages = if contract.pending?
        []
      else
        selected_cards
          .filter_map { |card| rate_card_usage(card) }
          .sort_by { |usage| usage_order(usage) }
      end

      result.amount_cents = result.rate_card_usages.sum(&:amount_cents)
      result.taxes_amount_cents = result.rate_card_usages.sum(&:taxes_amount_cents)
      result.total_amount_cents = result.amount_cents + result.taxes_amount_cents
      result
    end

    private

    attr_reader :contract, :timestamp, :apply_taxes, :filters

    delegate :customer, to: :contract

    # Filtered after the version selection, so that a superseded version never stands in for
    # the card that replaced it.
    def selected_cards
      effective_cards.select { |card| matches_filters?(card) }
    end

    def effective_cards
      cards = contract.applied_rate_cards
        .includes(
          {rate_card: [:rates, :product_filter, {product: [:billable_metric, :product_category]}]},
          {rate_phases: :rate_override},
          :organization,
          :product
        )
        .order(:effective_date, :created_at, :id)
        .to_a
      date = timestamp.in_time_zone(customer.applicable_timezone).to_date

      ContractRateCards::SelectEffectiveService.call!(contract_rate_cards: cards, date:).contract_rate_cards
    end

    def matches_filters?(card)
      rate_card = card.rate_card
      values = {
        rate_card_code: rate_card.code,
        product_code: rate_card.product.code,
        product_filter_code: rate_card.product_filter&.code,
        product_type: rate_card.product.product_type
      }

      values.all? { |name, value| filters[name].blank? || filters[name] == value }
    end

    def rate_card_usage(card)
      return if card.rate_card.rates.empty?

      schedule = Billing::RateCards::BuildScheduleService.call!(
        contract_rate_card: card, resume_from_billing_segments: false
      ).schedule
      billable_segment = schedule.segment_covering(timestamp)
      return unless billable_segment

      billing_segment = BillingSegments::BuildEventSegmentService.call!(
        contract_rate_card: card, billable_segment:
      ).billing_segment

      RateCardUsage.new(
        contract_rate_card: card,
        billing_segment:,
        rate_phase: card.rate_phases.find { |phase| phase.code == billable_segment.rate_phase_code },
        fees: taxed(compute_fees(billing_segment))
      )
    end

    # Oldest window first; on the same start, the one closing first.
    def usage_order(usage)
      [usage.billing_segment.started_at, usage.billing_segment.ended_at, usage.contract_rate_card.rate_card.code]
    end

    def compute_fees(billing_segment)
      if billing_segment.contract_rate_card.rate_card.product.metered?
        Fees::ChargeService.call!(
          invoice: nil,
          metered_item: Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:),
          billing_context:,
          options: Fees::ChargeService::Options.new(context: :current_usage)
        ).fees
      else
        [BillingSegments::Fees::ComputeService.call!(billing_segment:).fee]
      end
    end

    def taxed(fees)
      if apply_taxes
        fees.each { |fee| Fees::ApplyTaxesService.call!(fee:, customer:) }
      end

      fees
    end

    def billing_context
      @billing_context ||= Billing::Context.from(contract:)
    end
  end
end
