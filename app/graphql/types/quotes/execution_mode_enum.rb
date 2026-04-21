# frozen_string_literal: true

module Types
  module Quotes
    class ExecutionModeEnum < Types::BaseEnum
      Quote::EXECUTION_MODES.keys.each do |mode|
        value mode
      end
    end
  end
end
