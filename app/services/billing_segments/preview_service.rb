# frozen_string_literal: true

module BillingSegments
  # What the calendar would produce for a set of contracts over a window, writing nothing.
  #
  # It answers from the schedule alone, never from stored segments, so a contract that has
  # already billed previews exactly like one that has not — the same question, the same answer.
  class PreviewService < BaseService
    Result = BaseResult[:previews, :next_billing_at]

    # One row: the attachment that would bill, and what it would bill.
    Preview = Data.define(:contract_rate_card, :billable_segment)

    def initialize(contracts:, from:, to:)
      @contracts = contracts
      @from = from
      @to = to
      super
    end

    def call
      previews = []
      next_billing_ats = []

      cards.find_each do |card|
        schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule

        schedule.segments_overlapping(from...to).each do |billable_segment|
          previews << Preview.new(contract_rate_card: card, billable_segment:)
        end
        next_billing_ats << schedule.next_billing_at(after: to)
      end

      result.previews = previews
      # The soonest instant anything bills, not the latest: a contract mixing a monthly card
      # and a yearly one would otherwise report the yearly one and hide next month's invoice.
      result.next_billing_at = next_billing_ats.compact.min
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contracts, :from, :to

    # Scoped to what the calendar can schedule rather than to what is due: a preview shows a
    # card that has not reached its clock yet, which is most of the point of asking.
    def cards
      ContractRateCard.schedulable(to)
        .where(contract_id: contracts.map(&:id))
        .includes(
          :rate_card,
          {rate_phases: :rate_override},
          contract: [:customer, {catalog_plan: {applied_rate_cards: :rate_phases}}]
        )
    end
  end
end
