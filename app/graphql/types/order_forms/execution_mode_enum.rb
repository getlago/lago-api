# frozen_string_literal: true

module Types
  module OrderForms
    class ExecutionModeEnum < Types::BaseEnum
      graphql_name "OrderFormExecutionModeEnum"

      ::OrderForms::MarkAsSignedService::EXECUTION_MODES.each do |mode|
        value mode
      end
    end
  end
end
