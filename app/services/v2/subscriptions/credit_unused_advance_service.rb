# frozen_string_literal: true

module V2
  module Subscriptions
    # Credits the paid-but-unused remainder of a terminated subscription's ADVANCE items.
    # Advance bills the whole period up front, so ending mid-period leaves an unused
    # portion on each item's fee. Because a credit note belongs to a single invoice, the
    # creditable fees are grouped by invoice and one credit note is issued per invoice
    # (one item per fee) — so items billed together (same billing_at → same invoice)
    # collapse into a single credit note instead of one per item.
    #
    # The credited fraction is the complement of the consumed fraction (symmetric with
    # how an arrears termination charges only the used days). Net of any credit notes
    # already issued on the fee, so it is idempotent. Reuses Lago's CreditNotes machinery
    # (CreateService + ApplyTaxesService); only :credit for now, refund/offset later.
    class CreditUnusedAdvanceService < BaseService
      Result = BaseResult[:credit_notes]

      def initialize(subscription:, terminated_at:)
        @subscription = subscription
        @terminated_at = terminated_at
        super
      end

      def call
        result.credit_notes = creditable_entries.group_by { |entry| entry[:fee].invoice }.filter_map do |invoice, entries|
          create_credit_note(invoice, entries)
        end
        result
      end

      private

      attr_reader :subscription, :terminated_at

      # One {fee:, amount_cents:} per advance item that still has an unused, uncredited
      # remainder on the period covering the termination.
      def creditable_entries
        subscription.subscription_rate_cards.filter_map { |item| creditable_entry(item) }
      end

      def creditable_entry(subscription_rate_card)
        rate = resolve_rate(subscription_rate_card)
        return unless rate&.rate_card&.billing_timing == "advance"

        cycle = open_cycle(subscription_rate_card)
        return unless cycle

        fee = cycle.invoice.fees.find_by(invoiceable: subscription_rate_card.product_item)
        return unless fee

        amount_cents = creditable_amount_cents(fee, cycle, subscription_rate_card, rate)
        return unless amount_cents.positive?

        {fee:, amount_cents:}
      end

      # The already-done advance cycle whose period the termination falls in — the one
      # that billed the period we're now partially refunding.
      def open_cycle(subscription_rate_card)
        BillingCycle.done
          .where(subscription_rate_card:)
          .where("period_from <= ? AND period_to >= ?", terminated_at, terminated_at)
          .where.not(invoice_id: nil)
          .order(billing_at: :desc)
          .first
      end

      # Unused fraction of the billed period × the fee, net of credit notes already on it.
      def creditable_amount_cents(fee, cycle, subscription_rate_card, rate)
        credit_ratio = 1 - boundaries(subscription_rate_card, rate).proration_ratio(cycle.period_from, terminated_at)
        amount = BigDecimal(fee.amount_cents) * credit_ratio
        amount -= fee.credit_note_items.sum(:amount_cents)
        amount.positive? ? amount : BigDecimal(0)
      end

      def create_credit_note(invoice, entries)
        items = entries.map do |entry|
          {fee_id: entry[:fee].id, amount_cents: entry[:amount_cents].truncate(CreditNote::DB_PRECISION_SCALE)}
        end

        credit_result = CreditNotes::CreateService.call(
          invoice:,
          credit_amount_cents: total_credit_amount_cents(invoice, items),
          items:,
          reason: :order_cancellation,
          automatic: true
        )
        credit_result.raise_if_error!
        credit_result.credit_note
      end

      # Total credit incl taxes and net of coupons for one invoice's items — the same
      # adjustment the legacy termination path applies before handing amounts to CreateService.
      def total_credit_amount_cents(invoice, items)
        tax_items = items.map { |item| CreditNoteItem.new(fee_id: item[:fee_id], precise_amount_cents: item[:amount_cents]) }
        taxes_result = CreditNotes::ApplyTaxesService.call(invoice:, items: tax_items)

        (
          items.sum { |item| item[:amount_cents] } -
          taxes_result.coupons_adjustment_amount_cents +
          taxes_result.precise_taxes_amount_cents
        ).round
      end

      def resolve_rate(subscription_rate_card)
        SubscriptionRateCards::ResolveRateService
          .call(subscription_rate_card:, datetime: terminated_at)
          .rate
      end

      def boundaries(subscription_rate_card, rate)
        BillingPeriods::Boundaries.new(
          billing_anchor_date: subscription_rate_card.billing_anchor_date,
          interval_count: rate.billing_interval_count,
          interval_unit: rate.billing_interval_unit,
          timezone: subscription.customer.applicable_timezone
        )
      end
    end
  end
end
