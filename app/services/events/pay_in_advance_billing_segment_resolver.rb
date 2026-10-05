# frozen_string_literal: true

module Events
  class PayInAdvanceBillingSegmentResolver < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(event:)
      @event = event
      super
    end

    def call
      unless organization.product_catalog_enabled? && billable_metric
        result.billing_segments = []
        return result
      end

      result.billing_segments = billing_segments
      result
    end

    private

    attr_reader :event

    delegate :billable_metric, :organization, to: :event

    def billing_segments
      cards = ContractRateCard
        .joins(:contract, rate_card: :product)
        .where(
          contracts: {external_id: event.external_subscription_id, status: Contract::BILLABLE_STATUSES},
          products: {billable_metric_id: billable_metric.id, product_type: :metered},
          organization_id: organization.id
        )
        .includes(:rate_card, contract: {customer: :billing_entity})
        .order(:effective_date, :created_at, :id)
        .to_a

      return [] if cards.empty?

      event_date = event.timestamp.in_time_zone(cards.first.contract.customer.applicable_timezone).to_date
      selected_cards = cards.group_by { |card| [card.contract_id, card.rate_card.product_id, card.rate_card.product_filter_id] }
        .filter_map do |_key, versions|
          first_later_index = versions.bsearch_index { |card| card.effective_date > event_date } || versions.length
          versions[first_later_index - 1] unless first_later_index.zero?
        end

      # An effective arrears replacement must supersede the older advance card.
      selected_cards.select! { |card| card.rate_card.advance? }

      return [] if selected_cards.empty?

      ActiveRecord::Associations::Preloader.new(
        records: selected_cards, associations: [{rate_card: :rates}, {rate_phases: :rate_override}]
      ).call

      pricing_unit_codes = selected_cards.filter_map { |card| card.rate_card.applied_pricing_unit_code }.uniq
      pricing_units = organization.pricing_units.where(code: pricing_unit_codes).index_by(&:code) if pricing_unit_codes.any?

      selected_cards.filter_map { |card| segment_for(card, pricing_units || {}) }
    end

    def segment_for(card, pricing_units)
      return if card.rate_card.rates.empty?

      schedule = Billing::RateCards::BuildScheduleService.call!(
        contract_rate_card: card, resume_from_billing_segments: false
      ).schedule
      segment = schedule.segment_covering(event.timestamp)

      if segment
        BillingSegments::BuildEventSegmentService.call!(
          contract_rate_card: card, billable_segment: segment, pricing_units_by_code: pricing_units
        ).billing_segment
      end
    end
  end
end
