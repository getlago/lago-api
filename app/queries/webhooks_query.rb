# frozen_string_literal: true

class WebhooksQuery < BaseQuery
  Result = BaseResult[:webhooks]
  Filters = BaseFilters[:status]

  def initialize(webhook_endpoint:, pagination: DEFAULT_PAGINATION_PARAMS, filters: {}, search_term: nil, order: nil)
    @webhook_endpoint = webhook_endpoint
    super(organization: webhook_endpoint.organization, pagination:, filters:, search_term:, order:)
  end

  def call
    webhooks = base_scope.result
    webhooks = paginate(webhooks)
    webhooks = apply_consistent_ordering(
      webhooks,
      default_order: {updated_at: :desc, created_at: :desc}
    )

    webhooks = with_status(webhooks) if filters.status.present?

    result.webhooks = webhooks
    result
  end

  private

  attr_reader :webhook_endpoint

  def base_scope
    webhook_endpoint.webhooks.ransack(search_params)
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
