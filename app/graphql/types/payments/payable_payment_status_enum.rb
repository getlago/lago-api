# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Payments
    class PayablePaymentStatusEnum < Types::BaseEnum
      Payment::PAYABLE_PAYMENT_STATUS.each do |type|
        value type
      end
    end
  end
end
