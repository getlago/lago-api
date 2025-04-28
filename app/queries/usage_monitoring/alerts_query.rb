# frozen_string_literal: true

module UsageMonitoring
  class AlertsQuery < BaseQuery
    Result = BaseResult[:alerts]
    Filters = BaseFilters[:subscription_external_id]

    def call
      alerts = paginate(base_scope)
      alerts = apply_consistent_ordering(alerts)

      alerts = with_external_subscription(alerts) if filters.subscription_external_id.present?

      result.alerts = alerts
      result
    end

    private

    def base_scope
      UsageMonitoring::Alert.where(organization:)
    end

    def with_external_subscription(scope)
      scope.where(subscription_external_id: filters.subscription_external_id)
    end
  end
end
