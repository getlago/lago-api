# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertService < BaseService
    Result = BaseResult

    def initialize(alert:)
      @alert = alert
      @organization = alert.organization
      super
    end

    def call
      return result unless organization.using_lifetime_usage?
      return result unless alert.alert_type == "billable_metric_lifetime_usage_units"
      return result unless subscription

      charge_ids = subscription.plan.charges.where(billable_metric_id: alert.billable_metric_id).ids
      return result if charge_ids.empty?

      usage_filters = UsageFilters.new(full_usage: true, filter_by_charge_id: charge_ids)
      usage_for_charges_result = ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false,
        with_cache: true,
        usage_filters:
      )
      return result unless usage_for_charges_result.success?

      ProcessAlertService.call(alert:, subscription:, current_metrics: usage_for_charges_result.usage)

      result
    end

    private

    attr_reader :alert, :organization

    def subscription
      @subscription ||= Subscription.active.where(organization_id: alert.organization_id, external_id: alert.subscription_external_id).first
    end
  end
end
