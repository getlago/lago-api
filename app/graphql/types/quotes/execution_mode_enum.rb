# frozen_string_literal: true

module Types
  module Quotes
    class ExecutionModeEnum < Types::BaseEnum
      graphql_name "QuoteExecutionModeEnum"

      Quote::EXECUTION_MODES.keys.each do |mode|
        value mode
      end
    end
  end
end
