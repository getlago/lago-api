# frozen_string_literal: true

module Types
  module Charges
    class InvoicingStrategyEnum < Types::BaseEnum
      Charge::INVOICING_STRATEGIES.each do |type|
        value type
      end
    end
  end
end
