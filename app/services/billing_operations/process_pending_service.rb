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
      periodic_card_ids = Set.new
      units_histories = {}
      processing_error = nil
      Customers::LockService.call!(customer:, scope: :billing_schedule, transaction: false) do
        loop do
          ScheduleService.call!(customer:, timestamp:) if units_changes_pending?
          periodic = ProcessService.call(customer:, timestamp:, excluded_periodic_card_ids: periodic_card_ids, units_histories:)
          processing_error ||= periodic.error
          result.invoices.concat(periodic.invoices)
          periodic_card_ids.merge(periodic.periodic_card_ids)
          ScheduleService.call!(customer:, timestamp:) if units_changes_pending?
          reconciliation = ReconcileAdvanceCoverageService.call(customer:, timestamp:, units_histories:)
          processing_error ||= reconciliation.error
          result.invoices.concat(reconciliation.invoices)
          break if reconciliation.failure? || reconciliation.processed_operation_ids.empty?
        end
      end
      processing_error ? result.fail_with_error!(processing_error) : result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error.result.error)
    end

    private

    attr_reader :customer, :timestamp

    def units_changes_pending?
      customer.billing_operations.pending.units_changes
        .where(organization_id: customer.organization_id, billing_at: ..timestamp).exists?
    end
  end
end
