# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      BillingSegment = Data.define(:billing_segment, :filter) do
        include FilterSource

        delegate :billable_metric, to: :product

        delegate :target_key, to: :billing_segment

        def with_filter(filter)
          self.class.new(billing_segment:, filter:)
        end

        private

        def filter_owner
          product
        end

        def product
          billing_segment.contract_rate_card.product
        end
      end
    end
  end
end
