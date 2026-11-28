# frozen_string_literal: true

module BillingOperations
  module Schedule
    # Fills due obligations before the optional next plan; caller holds the customer billing-schedule lock.
    class DueOperationsService < BaseService
      Result = BaseResult[:billing_operations]

      def initialize(contract_rate_card:, next_planned_operation:, schedule:, timestamp:)
        @contract_rate_card = contract_rate_card
        @next_planned_operation = next_planned_operation
        @schedule = schedule
        @timestamp = timestamp
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

      attr_reader :contract_rate_card, :next_planned_operation, :schedule, :timestamp

      def action_type
        @action_type ||= contract_rate_card.periodic_billing_action
      end

      def last_periodic_operation
        return @last_periodic_operation if defined?(@last_periodic_operation)

        operations = contract_rate_card.billing_operations.periodic
          .where(organization_id: contract_rate_card.organization_id, action_type:, cancelled_at: nil)
          .where(billing_at: ..timestamp)
        operations = operations.where(billing_at: ...next_planned_operation.billing_at) if next_planned_operation
        @last_periodic_operation = operations.order(billing_at: :desc, created_at: :desc, id: :desc).first
      end

      def create_due_operations
        from = last_periodic_operation&.target_cycle_started_at || contract_rate_card.effective_date_in_customer_timezone
        previous_billing_at = last_periodic_operation&.billing_at
        cutoff = next_planned_operation ? [timestamp, next_planned_operation.billing_at].min : timestamp
        due = schedule.obligations_due_by(cutoff, from:, after: previous_billing_at)
        due.filter_map do |obligation|
          plan = PlannedOperation.from_obligation(obligation, after: previous_billing_at)
          next unless plan.due_by?(timestamp, before: next_planned_operation&.billing_at)

          operation = BillingOperations::CreateService.call!(
            contract_rate_card:, action_type:, reason: "periodic_continuation", planned_operation: plan
          ).operation
          previous_billing_at = operation.billing_at
          operation
        end
      end
    end
  end
end
