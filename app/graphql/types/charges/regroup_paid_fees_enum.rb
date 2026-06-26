# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class RegroupPaidFeesEnum < Types::BaseEnum
      Charge::REGROUPING_PAID_FEES_OPTIONS.each do |type|
        value type
      end
    end
  end
end
