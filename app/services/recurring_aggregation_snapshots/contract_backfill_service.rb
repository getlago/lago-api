# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Writes, for each recurring rate card of a contract, the snapshots of the latest slice it closed, aggregated
  # as its close operation did, so reads need not wait for a slice to close with writes on. Slices are not
  # stored: those of the card's latest processed close operation are rebuilt from the schedule, and only the
  # last one is written, as a read only starts from the latest period.
  class ContractBackfillService < BaseService
    Result = BaseResult[:written_rate_cards, :skipped_rate_cards, :failed_rate_cards]

    def self.processed_closes
      BillingOperation.where(action_type: "close_metered_arrears", cancelled_at: nil).where.not(processed_at: nil)
    end

    def self.backfillable_rate_cards(organization)
      ContractRateCard
        .joins(rate_card: {product: :billable_metric})
        .where(
          organization_id: organization.id,
          billable_metrics: {recurring: true, aggregation_type: RecurringAggregationSnapshot::AGGREGATION_TYPES}
        )
        .where(id: processed_closes.where(organization_id: organization.id).select(:contract_rate_card_id))
    end

    def self.backfillable_contracts(organization)
      organization.contracts.active.where(id: backfillable_rate_cards(organization).select(:contract_id))
    end

    def initialize(contract:)
      @contract = contract

      super
    end

    def call
      return result.not_allowed_failure!(code: "contract_not_active") unless contract.active?

      result.written_rate_cards = []
      result.skipped_rate_cards = []
      result.failed_rate_cards = []

      started_at = Time.current

      rate_cards.each { backfill_rate_card(it, started_at) }

      result
    end

    private

    attr_reader :contract

    def backfill_rate_card(contract_rate_card, started_at)
      segment = latest_closed_segment(contract_rate_card)
      unless segment
        result.skipped_rate_cards << contract_rate_card
        return
      end

      metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment)
      charge_result = Fees::ChargeService.call(
        invoice: nil,
        metered_item:,
        billing_context:,
        options: Fees::ChargeService::Options.new(context: :snapshot_backfill, skip_adjusted_fees: true)
      )

      if charge_result.failure?
        result.failed_rate_cards << contract_rate_card
      elsif marker_written?(metered_item, since: started_at)
        result.written_rate_cards << contract_rate_card
      else
        result.skipped_rate_cards << contract_rate_card
      end
    rescue *BackfillService::CHARGE_ERRORS
      result.failed_rate_cards << contract_rate_card
    end

    def latest_closed_segment(contract_rate_card)
      operation = self.class.processed_closes
        .where(organization_id: contract.organization_id, contract_rate_card_id: contract_rate_card.id)
        .order(billing_at: :desc, id: :desc)
        .first
      return unless operation

      BillingOperations::ResolveSegmentsService.call!(operation:).segments.max_by(&:ended_at)
    end

    def billing_context
      @billing_context ||= Billing::Context.from(contract:)
    end

    def rate_cards
      self.class.backfillable_rate_cards(contract.organization)
        .where(contract_id: contract.id)
        .preload(:terms, contract: :customer, rate_card: {product: :billable_metric})
        .order(:created_at, :id)
    end

    # A slice without recurring units leaves its key without snapshots (see Fees::ChargeService)
    def marker_written?(metered_item, since:)
      RecurringAggregationSnapshot.key(metered_item:, billing_context:).snapshots.where(
        to_datetime: metered_item.boundaries.charges_to_datetime,
        watermark: (since - RecurringAggregationSnapshot::WATERMARK_LAG).floor(3)..
      ).exists?
    end
  end
end
