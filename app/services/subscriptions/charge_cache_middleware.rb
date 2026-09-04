# frozen_string_literal: true

module Subscriptions
  class ChargeCacheMiddleware
    EMPTY_ARRAY = [].freeze

    # The ingestion timestamp is indexed on neither store, so a backdated event cannot be detected
    # on read. This expiration is what bounds how long one stays invisible.
    DEFAULT_PRIOR_PERIODS_EXPIRATION = 1.day

    def initialize(subscription:, charge:, to_datetime:, cache: true, full_usage: false, prior_periods: false,
      context: nil, last_seen_at: nil)
      @subscription = subscription
      @charge = charge
      @to_datetime = to_datetime
      @cache = cache
      @full_usage = full_usage
      @prior_periods = prior_periods
      @context = context
      @last_seen_at = last_seen_at || {}
    end

    def self.prior_periods_expiration
      (ENV["LAGO_PRIOR_PERIODS_USAGE_CACHE_TTL_SECONDS"].presence || DEFAULT_PRIOR_PERIODS_EXPIRATION).to_i.seconds
    end

    def call(charge_filter:)
      return yield unless cache

      # Lazily invalidate the cache when a more recent event was ingested for this charge/filter.
      # last_seen_at is the { filter_id => timestamp } bucket for the current charge.
      invalidate_if_older_than = prior_periods ? nil : last_seen_at[charge_filter&.id]

      json = Subscriptions::ChargeCacheService.call(subscription:, charge:, charge_filter:, full_usage:, prior_periods:, context:, expires_in: cache_expiration, invalidate_if_older_than:) do
        yield
          .map do |fee|
            fee.attributes.merge(
              "pricing_unit_usage" => fee.pricing_unit_usage&.attributes,
              "presentation_breakdowns" => fee.presentation_breakdowns.map(&:attributes)
            )
          end
          .to_json
      end

      JSON.parse(json).map do |j|
        pricing_unit_usage = if j["pricing_unit_usage"].present?
          PricingUnitUsage.new(j["pricing_unit_usage"].slice(*PricingUnitUsage.column_names))
        end

        fee = Fee.new(
          **j.slice(*Fee.column_names),
          pricing_unit_usage:
        )

        j.fetch("presentation_breakdowns", EMPTY_ARRAY).each do |breakdown|
          fee.presentation_breakdowns.build(
            breakdown.slice(*PresentationBreakdown.column_names)
          )
        end

        fee
      end
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache, :full_usage, :prior_periods, :context, :last_seen_at

    def cache_expiration
      return self.class.prior_periods_expiration if prior_periods
      return 0 unless to_datetime

      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
