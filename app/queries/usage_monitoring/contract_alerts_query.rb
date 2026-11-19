# frozen_string_literal: true

module UsageMonitoring
  class ContractAlertsQuery < BaseQuery
    Result = BaseResult[:contract_alerts]
    Filters = BaseFilters[:contract_external_id, :created_at_from, :created_at_to]

    def call
      alerts = ContractAlert.where(organization:, contract_external_id: filters.contract_external_id)
        .includes(:thresholds, :product, :product_filter)
        .order(created_at: :desc, id: :desc)
      alerts = with_date_range(alerts, :created_at)

      result.contract_alerts = paginate(alerts)
      result
    rescue BaseService::FailedResult
      result
    end
  end
end
