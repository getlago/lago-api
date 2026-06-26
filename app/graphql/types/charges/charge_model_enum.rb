# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class ChargeModelEnum < Types::BaseEnum
      Charge::CHARGE_MODELS.each do |type|
        value type
      end
    end
  end
end
