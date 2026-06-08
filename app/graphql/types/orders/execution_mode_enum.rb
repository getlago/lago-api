# frozen_string_literal: true

module Types
  module Orders
    class ExecutionModeEnum < Types::BaseEnum
      graphql_name "OrderExecutionModeEnum"

      ::OrderForms::MarkAsSignedService::EXECUTION_MODES.each do |mode|
        value mode
      end
    end
  end
end
