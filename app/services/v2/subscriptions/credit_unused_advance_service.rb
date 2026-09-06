# frozen_string_literal: true

module V2
  module Subscriptions
    # Credits the paid-but-unused remainder of a terminated subscription's advance
    # items. Arrears items are skipped: their final usage is billed by the pending
    # BillingCycle created during item termination.
    #
    # Advance bills the whole period up front, so ending mid-period leaves an unused
    # portion on the already-invoiced fee. The billed segment is resolved through
    # Billing::BuildScheduleService, and the schedule's consumed_ratio gives the share of
    # it served up to terminated_at. The credited share is the complement of that ratio,
    # net of any credit notes already issued on the fee.
    #
    # THE RULE: the credited fraction is computed on the same basis the fee was priced on.
    # A rate change cuts a period into segments priced one by one, so the fee on the invoice
    # bought one segment and only that segment's own unused days come back. The fee and the
    # fraction are therefore read off the same period, resolved by the same rule.
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

        schedule = schedule_through(subscription_rate_card, cycle)
        return unless schedule

        segment = billed_segment(schedule)
        return unless segment

        fee = cycle.invoice.fees.find_by(invoiceable: subscription_rate_card.product)
        return unless fee

        amount_cents = creditable_amount_cents(schedule, fee, segment)
        return unless amount_cents.positive?

        {fee:, amount_cents:}
      end

      # How far billing ran: the end of the day the termination falls in. The customer entered
      # that day, so it is served and paid for, and only the days after it come back.
      def billed_through
        @billed_through ||= Billing::TerminationDay.billed_through(terminated_at, timezone: subscription.customer.applicable_timezone)
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
      #
      # The fraction is a share of the segment, because the fee is the price of the segment:
      # a fraction read off any other period would refund days this fee never charged for.
      def creditable_amount_cents(schedule, fee, segment)
        consumed_ratio = schedule.consumed_ratio(segment:, at: billed_through)
        amount = BigDecimal(fee.amount_cents) * (1 - consumed_ratio)
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

      # The slice of the paid-up-front period the card was in when it ended: the one window
      # covering terminated_at. Selected by overlap — the same rule #open_cycle applies to
      # the persisted row — so the fee and the fraction always come off one period. Read off
      # the due list instead, the two disagreed on a termination falling exactly on a cycle
      # boundary: the fee came from the cycle opening at that instant while the fraction
      # came from the previous, fully consumed one, and nothing was credited at all.
      def billed_segment(schedule)
        schedule.segments_overlapping(terminated_at..terminated_at).last
      end

      # The schedule as it stood before the termination clipped it. The item's `ended_at`
      # was set to terminated_at moments ago, and a schedule stopping there can produce
      # neither the segment opening at that instant nor the whole of the one containing it.
      # Running it to the end of the billed period restores both, so the segment resolved
      # here is the segment that was charged — the same window #open_cycle read off the row.
      def schedule_through(subscription_rate_card, cycle)
        build = Billing::BuildScheduleService.call(subscription_rate_card:, ends_at: exclusive_end_of(cycle))
        build.success? ? build.schedule : nil
      end

      # `period_to` is the last instant the period covers; the engine's windows are
      # half-open, so its end is the microsecond after that — the one BillingCycles::
      # ScheduleService subtracted when it wrote the row.
      def exclusive_end_of(cycle)
        cycle.period_to + BillingCycles::ScheduleService::PERIOD_END_PRECISION
      end
    end
  end
end
