# frozen_string_literal: true

module Types
  module Orders
    class ExecutionModeEnum < Types::BaseEnum
      Order::EXECUTION_MODES.keys.each do |mode|
        value mode
      end
    end
  end
end
