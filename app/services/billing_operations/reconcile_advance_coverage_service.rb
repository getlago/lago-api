# frozen_string_literal: true

module BillingOperations
  class ReconcileAdvanceCoverageService < BaseProcessService
    private

    def action_types
      ["reconcile_advance_coverage"]
    end

    def process_due_operations
      loop do
        operations = due_operations.to_a
        break if operations.empty?

        process_invoice_groups(operations)
        break if @processing_error
      end
    end
  end
end
