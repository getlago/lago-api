# frozen_string_literal: true

module IntegrationMappings
  class NetsuiteMappingsQuery < BaseQuery
    def call(search_term:, integration_id:, page:, limit:, filters: {})
      @search_term = search_term
      @integration_id = integration_id

      netsuite_mappings = base_scope.result
      netsuite_mappings = netsuite_mappings.where(integration_id:) if integration_id.present?

      if filters[:mappable_type].present?
        netsuite_mappings = netsuite_mappings.where(mappable_type: filters[:mappable_type])
      end

      netsuite_mappings = netsuite_mappings.order(created_at: :desc).page(page).per(limit)

      result.netsuite_mappings = netsuite_mappings
      result
    end

    private

    attr_reader :search_term

    def base_scope
      ::IntegrationMappings::NetsuiteMapping
        .joins(:integration)
        # .includes(:mappable)
        .where(integration: { organization_id: organization.id })
        .ransack(search_params)
    end

    def search_params
      return nil if search_term.blank?

      {
        m: 'or',
        mappable_of_AddOn_type_name_cont: search_term,
        mappable_of_AddOn_type_code_cont: search_term,
        mappable_of_BillableMetric_type_name_cont: search_term,
        mappable_of_BillableMetric_type_code_cont: search_term,
      }
    end
  end
end
