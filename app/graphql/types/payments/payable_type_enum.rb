# frozen_string_literal: true

module Types
  module Payments
    class PayableTypeEnum < Types::BaseEnum
      Payment::PAYABLE_TYPES.each do |type|
        value type
      end
    end
  end
end
