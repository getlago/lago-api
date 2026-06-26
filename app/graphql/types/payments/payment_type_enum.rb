# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Payments
    class PaymentTypeEnum < Types::BaseEnum
      Payment::PAYMENT_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
