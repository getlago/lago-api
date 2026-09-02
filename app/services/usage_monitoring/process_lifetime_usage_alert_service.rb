# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertService < BaseService
    Result = BaseResult

    def initialize(alert:, subscription: nil)
      @alert = alert
      @subscription = subscription
      super
    end

    def call
      return result unless alert.alert_type == "billable_metric_lifetime_usage_units"
      return result unless subscription
      return result unless subscription.active?

      billable_metric_id = alert.billable_metric_id
      charge_ids = subscription.plan.charges.where(billable_metric_id:).ids
      return result if charge_ids.empty?

      usage_filters = UsageFilters.new(full_usage: true, filter_by_charge_id: charge_ids)
      usage_for_charges_result = ::Invoices::CustomerUsageService.call!(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false,
        with_cache: true,
        usage_filters:
      )

      # The usage was filtered for one metric, and evaluation reloads the alert under its lock, so a metric
      # changed in between would be measured against usage it does not appear in and read as no usage at all.
      return result unless Alert.where(id: alert.id, billable_metric_id:).exists?

      ProcessAlertService.call(alert:, alertable: subscription, current_metrics: usage_for_charges_result.usage)

      result
    end

    private

    attr_reader :alert, :organization, :subscription
  end
end
