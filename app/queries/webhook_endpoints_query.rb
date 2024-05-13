# frozen_string_literal: true

class WebhookEndpointsQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    webhook_endpoints = base_scope.result
    webhook_endpoints = webhook_endpoints.where(id: filters[:ids]) if filters[:ids].present?
    webhook_endpoints = webhook_endpoints.order(:webhook_url).page(page).per(limit)

    result.webhook_endpoints = webhook_endpoints
    result
  end

  private

  attr_reader :search_term

  def base_scope
    WebhookEndpoint.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {webhook_url_cont: search_term, m: 'or'}
  end
end
