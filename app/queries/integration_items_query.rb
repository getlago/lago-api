# frozen_string_literal: true

class IntegrationItemsQuery < BaseQuery
  def call(search_term:, integration_id:, page:, limit:, filters: {})
    @search_term = search_term
    @integration_id = integration_id

    integration_items = base_scope.result
    integration_items = integration_items.where(integration_id:) if integration_id.present?
    integration_items = integration_items.where(item_type: filters[:item_type]) unless filters[:item_type].nil?
    integration_items = integration_items.order(external_name: :asc).page(page).per(limit)

    result.integration_items = integration_items
    result
  end

  private

  attr_reader :search_term

  def base_scope
    IntegrationItem.joins(:integration).where(integration: {organization_id: organization.id}).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      external_name_cont: search_term,
      external_id_cont: search_term,
      external_account_code_cont: search_term,
    }
  end
end
