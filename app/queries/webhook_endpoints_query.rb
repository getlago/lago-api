# frozen_string_literal: true

class WebhookEndpointsQuery < BaseQuery
  Result = BaseResult[:webhook_endpoints]
  Filters = BaseFilters[:created_at_from, :created_at_to]

  def call
    webhook_endpoints = base_scope.result
    webhook_endpoints = with_date_range(webhook_endpoints, :created_at)
    webhook_endpoints = apply_consistent_ordering(
      webhook_endpoints,
      default_order: {webhook_url: :asc, created_at: :desc}
    )

    result.webhook_endpoints = paginate(webhook_endpoints)
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def base_scope
    WebhookEndpoint.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {webhook_url_cont: search_term, m: "or"}
  end
end
