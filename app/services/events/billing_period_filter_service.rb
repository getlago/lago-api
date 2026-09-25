# frozen_string_literal: true

module Events
  class BillingPeriodFilterService < BaseService
    Result = BaseResult[:filter_targets]

    # precomputed_filters maps a charge served from the pre-aggregated usage buckets to the charge
    # filter ids those buckets hold usage for, nil being the default bucket. Such a charge is
    # resolved from them rather than from the events store.
    def self.for_charges!(subscription:, boundaries:, codes: nil, with_last_seen_at: true, precomputed_filters: {})
      call!(
        resolver: BillingPeriodFilters::ChargesResolver.new(
          subscription:,
          boundaries:,
          codes:,
          with_last_seen_at:,
          precomputed_filters:
        )
      )
    end

    def self.for_billing_segments!(billing_segments:, codes: nil, with_last_seen_at: true)
      call!(
        resolver: BillingPeriodFilters::BillingSegmentsResolver.new(
          billing_segments:,
          codes:,
          with_last_seen_at:
        )
      )
    end

    def initialize(resolver:)
      @resolver = resolver
      super
    end

    # Return the target/filter pairs that will be used in the billing or usage computation.
    #
    # result.filter_targets is a nested hash:
    # { target_key => { filter_id => last_seen_at } } (nil filter is the default bucket).
    def call
      result.filter_targets = resolver.filter_targets
      result
    end

    private

    attr_reader :resolver
  end
end
