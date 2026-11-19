# frozen_string_literal: true

module BillingObligations
  class PreviewService < BaseService
    Result = BaseResult[:billing_obligations, :next_billing_at]
    Preview = Data.define(:contract_rate_card, :obligation)

    def initialize(contracts:, start_on:, end_on:)
      @contracts = contracts
      @start_on = start_on
      @end_on = end_on
      super
    end

    def call
      now = Time.current
      result.billing_obligations = []
      cards.find_each do |card|
        contract = card.contract
        timezone = contract.customer.applicable_timezone
        from = start_on&.in_time_zone(timezone) || contract.started_at || now
        to = end_on&.in_time_zone(timezone)&.end_of_day || now
        schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
        schedule.each_obligation_overlapping(from:, to:) do |obligation|
          result.billing_obligations << Preview.new(card, obligation)
        end
        upcoming = schedule.obligation_at(to)
        upcoming = schedule.next_obligation(from: to) unless upcoming && upcoming.billing_at > to
        next_at = upcoming&.billing_at
        result.next_billing_at = [result.next_billing_at, next_at].compact.min
      end
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contracts, :start_on, :end_on

    def cards
      ContractRateCard.priced.starting_before_contract_end
        .where(organization_id: contracts.map(&:organization_id), contract_id: contracts.map(&:id))
        .preload(rate_card: [:rates, {product: :billable_metric}], rate_phases: :rate_override, contract: {customer: :billing_entity})
    end
  end
end
