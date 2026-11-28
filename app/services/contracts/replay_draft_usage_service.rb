# frozen_string_literal: true

module Contracts
  # Bills the usage priced in advance that a contract received while it was a draft. The pay in
  # advance path skips a contract that is not billable, so a draft published after its start
  # replays its events from its start. Each event goes through Events::PayInAdvanceService, which
  # skips an event already billed on the same card: a replay run twice, or racing the live path,
  # bills each event once.
  class ReplayDraftUsageService < BaseService
    Result = BaseResult

    # Bounds the rows held at once, and replays them in timestamp order, which stateful
    # aggregations (sum with negative values, unique count, custom) price from.
    SLICE = 1.day

    def initialize(contract:, published_at:)
      @contract = contract
      @published_at = published_at
      super
    end

    def call
      return result unless contract.active? && contract.started_at < published_at

      billable_metric_codes.each do |code|
        each_event(code) do |event|
          Events::PayInAdvanceService.call!(event: Events::CommonFactory.new_instance(source: event))
        end
      end

      result
    end

    private

    attr_reader :contract, :published_at

    delegate :organization, to: :contract

    def billable_metric_codes
      BillableMetric.where(
        id: Product.metered.where(
          id: RateCard.where(id: contract.applied_rate_cards.select(:rate_card_id), billing_timing: :advance).select(:product_id)
        ).select(:billable_metric_id)
      ).order(:code).pluck(:code)
    end

    # No upper bound: an event ingested while the publication committed, or sent during the
    # draft with a later timestamp, was not billed by the live path either. The last slice is
    # open-ended. Slices share their bounds, and the dedup absorbs an event read twice.
    def each_event(code, &)
      from = contract.started_at

      loop do
        to = from + SLICE
        last_slice = to > Time.current
        store(code, from:, to: (to unless last_slice)).events(force_from: true, ordered: true).each(&)
        break if last_slice

        from = to
      end
    end

    def store(code, from:, to:)
      Events::Stores::StoreFactory.new_instance(
        organization:,
        billing_context: Billing::Context.from(contract:),
        boundaries: {from_datetime: from, to_datetime: to},
        code:
      )
    end
  end
end
