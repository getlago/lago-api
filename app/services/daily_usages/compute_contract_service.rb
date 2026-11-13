# frozen_string_literal: true

module DailyUsages
  # Records a contract's usage of a day, one daily usage per metered rate card, as
  # DailyUsages::ComputeService does for a subscription.
  class ComputeContractService < BaseService
    Result = BaseResult[:daily_usages]

    def initialize(contract:, timestamp:)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      result.daily_usages = []
      return result if contract.daily_usages.exists?(usage_date:)
      return result if terminated_before_usage_date?

      daily_usages = rate_card_usages.filter_map do |rate_card_usage|
        rate_card_usage = rate_card_usage.with(fees: rate_card_usage.fees.select(&:non_zero?))
        next if rate_card_usage.fees.empty?

        DailyUsage.new(
          organization: contract.organization,
          customer: contract.customer,
          contract:,
          contract_rate_card: rate_card_usage.contract_rate_card,
          external_contract_id: contract.external_id,
          usage: ::V1::DailyUsages::RateCardUsageSerializer.new(rate_card_usage).serialize,
          from_datetime: rate_card_usage.billing_segment.started_at,
          to_datetime: rate_card_usage.billing_segment.ended_at,
          refreshed_at: timestamp,
          usage_date:
        )
      end

      ActiveRecord::Base.transaction do
        daily_usages.each do |daily_usage|
          daily_usage.usage_diff = DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
          daily_usage.save!
        end
      end

      result.daily_usages = daily_usages
      result
    end

    private

    attr_reader :contract, :timestamp

    # Each card is read on the window open at the end of the usage date. On a card's billing day,
    # that is the window which just closed, so its last day is recorded here: a subscription
    # skips that day and leaves it to its periodic invoice, as its usage cache is not reliable
    # across the boundary, but contract usage is computed from the billing segment without that
    # cache. The next day reads the new window, whose diff restarts from its full usage.
    def rate_card_usages
      Contracts::CurrentUsageService.call(
        contract:,
        timestamp: usage_timestamp,
        apply_taxes: false,
        filters: {product_type: Product::PRODUCT_TYPES[:metered]}
      ).raise_if_error!.rate_card_usages
    end

    # A contract terminated during the day is read at its last instant: its schedule ends there.
    def usage_timestamp
      end_of_day = usage_date.in_time_zone(timezone).end_of_day
      return end_of_day unless contract.terminated_at

      [end_of_day, BillingSegment.inclusive_end(contract.terminated_at)].min
    end

    def terminated_before_usage_date?
      contract.terminated? && contract.terminated_at < usage_date.in_time_zone(timezone).beginning_of_day
    end

    def timezone
      @timezone ||= contract.customer.applicable_timezone
    end

    def usage_date
      @usage_date ||= timestamp.in_time_zone(timezone).to_date - 1.day
    end
  end
end
