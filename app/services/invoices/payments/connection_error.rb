# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Invoices
  module Payments
    class ConnectionError < StandardError
      def initialize(initial_error)
        @initial_error = initial_error
        super(initial_error.message)
      end

      attr_reader :initial_error
    end
  end
end
