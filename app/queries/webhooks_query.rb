# frozen_string_literal: true

class WebhooksQuery < BaseQuery
  Result = BaseResult[:webhooks]
  Filters = BaseFilters[:webhook_endpoint_id, :status]

  def call
    return result unless validate_filters.success?

    webhooks = base_scope.result
    webhooks = paginate(webhooks)
    webhooks = webhooks.order({updated_at: :desc, created_at: :desc})

    webhooks = with_status(webhooks) if filters.status.present?

    result.webhooks = webhooks
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::WebhooksQueryFiltersContract.new
  end

  def base_scope
    Webhook.where(organization:, webhook_endpoint_id: filters.webhook_endpoint_id).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      id_cont: search_term,
      webhook_type_cont: search_term
    }
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end
end
