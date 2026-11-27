# frozen_string_literal: true

module BillingOperations
  # Runs both processors in billing order while holding the customer's schedule lock.
  class ProcessPendingService < BaseService
    Result = BaseResult[:invoices]

    def initialize(customer:, timestamp:)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.invoices = []
      @periodic_card_ids = Set.new
      @units_histories = {}
      @processing_error = nil
      Customers::LockService.call!(customer:, scope: :billing_schedule, transaction: false) do
        loop do
          process_periodic_operations
          reconciliation = process_reconciliations
          break if reconciliation.failure? || reconciliation.processed_operation_ids.empty?
        end
      end
      processing_error ? result.fail_with_error!(processing_error) : result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error.result.error)
    end

    private

    attr_reader :customer, :timestamp, :periodic_card_ids, :units_histories, :processing_error

    def process_periodic_operations
      schedule_periodic_operations
      periodic = ProcessService.call(customer:, timestamp:, excluded_periodic_card_ids: periodic_card_ids, units_histories:)
      collect_result(periodic)
      periodic_card_ids.merge(periodic.periodic_card_ids)
    end

    def process_reconciliations
      schedule_periodic_operations
      reconciliation = ReconcileAdvanceCoverageService.call(customer:, timestamp:, units_histories:)
      collect_result(reconciliation)
      reconciliation
    end

    def collect_result(processing_result)
      @processing_error ||= processing_result.error
      result.invoices.concat(processing_result.invoices)
    end

    def schedule_periodic_operations
      ScheduleService.call!(customer:, timestamp:) if units_changes_pending?
    end

    def units_changes_pending?
      customer.billing_operations.pending.units_changes
        .where(organization_id: customer.organization_id, billing_at: ..timestamp).exists?
    end
  end
end
