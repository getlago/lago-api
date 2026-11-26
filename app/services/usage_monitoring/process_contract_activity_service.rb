# frozen_string_literal: true

module UsageMonitoring
  class ProcessContractActivityService < BaseService
    Result = BaseResult

    def initialize(contract_activity:)
      @contract_activity = contract_activity
      super
    end

    def call
      # A terminated or canceled contract is no longer evaluated; its alerts stay readable
      return delete_activity unless contract.active?

      alerts = contract.contract_alerts.load
      return delete_activity if alerts.empty?

      # Read once, before the usage: the usage holds at least the events ingested until then and prices the windows
      # open at that instant, so it is never stamped with a time from the other side of a renewal.
      measured_at = Time.current
      begin
        usage = Contracts::CurrentUsageService.call!(contract:, timestamp: measured_at, apply_taxes: false) # Never use taxes for alerting
      rescue
        # As for subscriptions, a usage that failed to build is not retried: the next activity evaluates the contract again
        delete_activity
        raise
      end

      exception_to_raise = nil

      alerts.each do |alert|
        ProcessAlertService.call!(alert:, alertable: contract, current_metrics: usage, measured_at:)
      rescue => e
        exception_to_raise ||= e
      end

      delete_activity
      raise exception_to_raise if exception_to_raise

      result
    end

    private

    attr_reader :contract_activity

    delegate :contract, to: :contract_activity

    def delete_activity
      contract_activity.delete
      result
    end
  end
end
