# frozen_string_literal: true

module BillingOperations
  module Schedule
    # Fills due obligations; caller holds the customer billing-schedule lock.
    class DueOperationsService < BaseService
      Result = BaseResult[:billing_operations]

      def initialize(contract_rate_card:, schedule:, timestamp:, previous_operation:)
        @contract_rate_card = contract_rate_card
        @schedule = schedule
        @timestamp = timestamp
        @previous_operation = previous_operation
        super
      end

      def call
        result.billing_operations = []
        return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card
        return result unless schedule && action_type

        created = ApplicationRecord.transaction(requires_new: true) { create_due_operations }
        result.billing_operations = created
        result
      rescue ActiveRecord::RecordInvalid => error
        result.record_validation_failure!(record: error.record)
      rescue BaseService::FailedResult => error
        result.fail_with_error!(error)
      end

      private

      attr_reader :contract_rate_card, :schedule, :timestamp, :previous_operation

      def action_type
        @action_type ||= contract_rate_card.periodic_billing_action
      end

      def create_due_operations
        from = previous_operation&.coverage_ended_at || contract_rate_card.effective_date_in_customer_timezone
        schedule.obligations_due_by(timestamp, from:, after: previous_operation&.billing_at).map do |obligation, billing_at|
          BillingOperations::CreateService.call!(
            contract_rate_card:, action_type:, reason: "periodic_continuation",
            planned_operation: PlannedOperation.new(obligation:, billing_at:)
          ).operation
        end
      end
    end
  end
end
