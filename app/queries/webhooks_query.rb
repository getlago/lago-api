# frozen_string_literal: true

class WebhooksQuery < BaseQuery
  def call(search_term:, page:, limit:, status: nil)
    @search_term = search_term

    webhooks = base_scope.result
    webhooks = webhooks.where(status:) if status.present?
    webhooks = webhooks.order(updated_at: :desc).page(page).per(limit)

    result.webhooks = webhooks
    result
  end

  private

  attr_reader :search_term

  def base_scope
    organization.webhooks.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      id_cont: search_term,
      webhook_type_cont: search_term,
    }
  end
end
