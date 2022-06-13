# frozen_string_literal: true

module Types
  module Charges
    class FixedAmountTargetEnum < Types::BaseEnum
      Charge::FIXED_AMOUNT_TARGETS.each do |type|
        value type
      end
    end
  end
end
