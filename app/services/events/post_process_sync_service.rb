# frozen_string_literal: true

module Events
  class PostProcessSyncService < PostProcessService
    private

    def handle_pay_in_advance
      return unless billable_metric
      charges.where(invoiceable: false).find_each do |charge|
        # TODO understand what this does, do we need sync for pay in advance?
        Fees::CreatePayInAdvanceJob.perform_now(charge:, event:)
      end

      # NOTE: ensure event is processable
      return if !billable_metric.count_agg? && event.properties[billable_metric.field_name].nil?
      invoices = []
      charges.where(invoiceable: true).find_each do |charge|
        charge_result = Invoices::CreatePayInAdvanceSyncChargeJob.perform_now(charge:, event:, timestamp: event.timestamp)
        invoices << charge_result.invoice if charge_result&.success?
      end

      result.invoices = invoices if invoices.any?
    end
  end
end
