# frozen_string_literal: true

module V2
  module Subscriptions
    # Credits the paid-but-unused remainder of a terminated subscription's advance
    # items. Arrears items are skipped: their final usage is billed by the pending
    # BillingCycle created during item termination.
    #
    # Advance bills the whole period up front, so ending mid-period leaves an unused
    # portion on the already-invoiced fee. The billed period is read from the cycle that
    # billed it, and the calendar gives the share of it consumed by the termination. The
    # credited share is the complement, net of any credit notes already on the fee.
    #
    # Because a credit note belongs to a single invoice, creditable fees are grouped
    # by invoice and one credit note is issued per invoice. Items billed together
    # collapse into a single credit note instead of one per item.
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
        subscription.applied_rate_cards.filter_map { |item| creditable_entry(item) }
      end

      def creditable_entry(subscription_rate_card)
        return unless subscription_rate_card.rate_card.advance?

        cycle = open_cycle(subscription_rate_card)
        return unless cycle

        fee = cycle.invoice.fees.find_by(invoiceable: subscription_rate_card.product)
        return unless fee

        amount_cents = creditable_amount_cents(fee, cycle)
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
      def creditable_amount_cents(fee, cycle)
        amount = BigDecimal(fee.amount_cents) * unused_ratio(cycle)
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

      # The share of the billed period the customer never got. The period comes from the
      # cycle that billed it, so a rate change since then cannot move the window the
      # credit is measured against.
      def unused_ratio(cycle)
        1 - calendar_for(cycle).elapsed_ratio(cycle.period_from, consumed_until(cycle))
      end

      # The termination day is billed in full, so consumption runs to the end of it rather
      # than to the instant itself. Without this a termination at midnight would count a
      # day less than the same termination at noon. Clamped to the cycle so terminating on
      # the closing boundary leaves nothing to credit.
      def consumed_until(cycle)
        [terminated_at.in_time_zone(timezone).end_of_day, cycle.period_to].min
      end

      def calendar_for(cycle)
        Billing::Calendar.new(
          anchor_date: cycle.subscription_rate_card.billing_anchor_date,
          interval: cycle.billing_interval,
          timezone:
        )
      end

      def timezone
        @timezone ||= subscription.customer.applicable_timezone
      end
    end
  end
end
