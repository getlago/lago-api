# frozen_string_literal: true

module BillingOperations
  # Processes at most one periodic obligation per card in each run.
  class ProcessService < BaseProcessService
    private

    def action_types
      BillingOperation::PERIODIC_ACTIONS.keys
    end

    def process_due_operations
      operations = due_operations.reject { excluded_periodic_card_ids.include?(it.contract_rate_card_id) }
      process_invoice_groups(operations)
    end
  end
end
