# frozen_string_literal: true

module Types
  module Quotes
    class VoidReasonEnum < Types::BaseEnum
      Quote::VOID_REASONS.keys.each do |status|
        value status
      end
    end
  end
end
