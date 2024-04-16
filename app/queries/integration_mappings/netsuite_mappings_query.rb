# frozen_string_literal: true

module IntegrationMappings
  class NetsuiteMappingsQuery < BaseQuery
    def call
      netsuite_mappings = paginate(base_scope)
      netsuite_mappings = netsuite_mappings.order(created_at: :desc)

      netsuite_mappings = with_integration_id(netsuite_mappings) if filters.integration_id
      netsuite_mappings = with_mappable_type(netsuite_mappings) if filters.mappable_type

      result.netsuite_mappings = netsuite_mappings
      result
    end

    private

    def base_scope
      ::IntegrationMappings::NetsuiteMapping.joins(:integration).where(integration: { organization: })
    end

    def with_integration_id(scope)
      scope.where(integration_id: filters.integration_id)
    end

    def with_mappable_type(scope)
      scope.where(mappable_type: filters.mappable_type)
    end
  end
end
