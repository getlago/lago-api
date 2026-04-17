# frozen_string_literal: true

module Types
  module Orders
    class ExecutionModeEnum < Types::BaseEnum
      graphql_name "OrderExecutionModeEnum"

      Order::EXECUTION_MODES.keys.each do |type|
        value type
      end
    end
  end
end
