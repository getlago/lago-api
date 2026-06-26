# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module AdjustedFees
    class AdjustedFeeTypeEnum < Types::BaseEnum
      AdjustedFee::ADJUSTED_FEE_TYPES.each do |type|
        value type
      end
    end
  end
end
