# frozen_string_literal: true

module Contracts
  # Prices, for each card effective at the timestamp, the billing window open at that instant,
  # through the code that invoices it.
  class CurrentUsageService < BaseService
    CardWindow = Data.define(:contract_rate_card, :billing_segment, :fees, :invoice_id)

    Result = BaseResult[:card_windows, :amount_cents, :taxes_amount_cents, :total_amount_cents]

    def initialize(contract:, timestamp: Time.current, apply_taxes: true)
      @contract = contract
      @timestamp = timestamp
      @apply_taxes = apply_taxes
      super
    end

    def call
      result.card_windows = effective_cards.filter_map { |card| card_window(card) }

      fees = result.card_windows.flat_map(&:fees)
      result.amount_cents = fees.sum(&:amount_cents)
      result.taxes_amount_cents = fees.sum(&:taxes_amount_cents)
      result.total_amount_cents = result.amount_cents + result.taxes_amount_cents
      result
    end

    private

    attr_reader :contract, :timestamp, :apply_taxes

    delegate :customer, to: :contract

    def effective_cards
      cards = contract.applied_rate_cards
        .includes({rate_card: [:rates, {product: :billable_metric}]}, {rate_phases: :rate_override})
        .order(:effective_date, :created_at, :id)
        .to_a
      date = timestamp.in_time_zone(customer.applicable_timezone).to_date

      ContractRateCards::SelectEffectiveService.call!(contract_rate_cards: cards, date:).contract_rate_cards
    end

    def card_window(card)
      return if card.rate_card.rates.empty?

      schedule = Billing::RateCards::BuildScheduleService.call!(
        contract_rate_card: card, resume_from_billing_segments: false
      ).schedule
      billable_segment = schedule.segment_covering(timestamp)
      return unless billable_segment

      billing_segment = BillingSegments::BuildEventSegmentService.call!(
        contract_rate_card: card, billable_segment:
      ).billing_segment

      CardWindow.new(
        contract_rate_card: card,
        billing_segment:,
        fees: taxed(compute_fees(billing_segment)),
        invoice_id: billed_invoice_id(card)
      )
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

    # Only a fixed advance card has billed its open window already, when the window opened.
    def billed_invoice_id(card)
      if card.rate_card.advance? && card.rate_card.product.fixed?
        card.billing_segments.status_done
          .where(started_at: ..timestamp, ended_at: timestamp..)
          .order(started_at: :desc)
          .pick(:invoice_id)
      end
    end

    def billing_context
      @billing_context ||= Billing::Context.from(contract:)
    end
  end
end
