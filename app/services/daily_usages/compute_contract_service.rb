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
      return result if Rails.cache.exist?(computed_cache_key)

      daily_usages = rate_card_usages.filter_map do |rate_card_usage|
        rate_card_usage = with_usage_only(rate_card_usage)
        next if rate_card_usage.segments.empty?

        DailyUsage.new(
          organization: contract.organization,
          customer: contract.customer,
          contract:,
          contract_rate_card: rate_card_usage.contract_rate_card,
          external_contract_id: contract.external_id,
          usage: ::V1::DailyUsages::RateCardUsageSerializer.new(rate_card_usage).serialize,
          from_datetime: rate_card_usage.started_at,
          to_datetime: rate_card_usage.ended_at,
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

      # A contract without usage saves no row, so the dedup on existing rows would let the next
      # runs of the scheduling window compute it again.
      Rails.cache.write(computed_cache_key, true, expires_in: 3.days) if daily_usages.empty?

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
    #
    # A segment-scoped card's window also ends inside the day when a rate takes effect then. Each
    # window aggregates from its own start, so the one that ended is read at its last instant too,
    # otherwise its events since the previous day would be in no row. A cycle-scoped card keeps
    # its window across the rate change, and prices both segments in it.
    def rate_card_usages
      day_start = usage_date.in_time_zone(timezone).beginning_of_day

      current_usages(usage_timestamp).flat_map do |usage|
        usages = [usage]
        # Walk back each card's windows that started inside the day: the one before each of
        # them ended there, and is read at its last instant.
        while (boundary = usages.last.started_at) > day_start
          previous = current_usages(BillingSegment.inclusive_end(boundary))
            .find { |u| u.contract_rate_card.id == usage.contract_rate_card.id }
          break unless previous && previous.started_at < boundary

          usages << previous
        end
        usages
      end
    end

    def with_usage_only(rate_card_usage)
      segments = rate_card_usage.segments.filter_map do |segment|
        fees = segment.fees.select(&:non_zero?)
        segment.with(fees:) if fees.any?
      end

      rate_card_usage.with(segments:)
    end

    def current_usages(at)
      @current_usages ||= {}
      @current_usages[at] ||= Contracts::CurrentUsageService.call(
        contract:,
        timestamp: at,
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

    # A contract ended by date is terminated at the local midnight after its last day, which is
    # the start of the next usage date and has nothing left to record.
    def terminated_before_usage_date?
      contract.terminated? && contract.terminated_at <= usage_date.in_time_zone(timezone).beginning_of_day
    end

    def computed_cache_key
      "daily_usages/contract/#{contract.id}/#{usage_date.iso8601}"
    end

    def timezone
      @timezone ||= contract.customer.applicable_timezone
    end

    def usage_date
      @usage_date ||= timestamp.in_time_zone(timezone).to_date - 1.day
    end
  end
end
