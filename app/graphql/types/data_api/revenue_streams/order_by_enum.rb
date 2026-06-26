# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataApi
    module RevenueStreams
      class OrderByEnum < Types::BaseEnum
        value :gross_revenue_amount_cents
        value :net_revenue_amount_cents
      end
    end
  end
end
