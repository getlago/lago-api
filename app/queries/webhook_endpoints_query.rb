# frozen_string_literal: true

class WebhookEndpointsQuery < BaseQuery
  def call
    webhook_endpoints = base_scope.result
    webhook_endpoints = paginate(webhook_endpoints)
    webhook_endpoints = webhook_endpoints.order(:webhook_url)

    result.webhook_endpoints = webhook_endpoints
    result
  end

  private

  def base_scope
    WebhookEndpoint.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {webhook_url_cont: search_term, m: 'or'}
  end
end
