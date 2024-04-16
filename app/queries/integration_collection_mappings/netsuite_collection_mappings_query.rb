# frozen_string_literal: true

module IntegrationCollectionMappings
  class NetsuiteCollectionMappingsQuery < BaseQuery
    def call
      netsuite_collection_mappings = paginate(base_scope)
      netsuite_collection_mappings = netsuite_collection_mappings.order(created_at: :desc)

      netsuite_collection_mappings = with_integration_id(netsuite_collection_mappings) if filters.integration_id
      netsuite_collection_mappings = with_mapping_type(netsuite_collection_mappings) if filters.mapping_type

      result.netsuite_collection_mappings = netsuite_collection_mappings
      result
    end

    private

    def base_scope
      ::IntegrationCollectionMappings::NetsuiteCollectionMapping
        .joins(:integration).where(integration: { organization: })
    end

    def with_integration_id(scope)
      scope.where(integration_id: filters.integration_id)
    end

    def with_mapping_type(scope)
      scope.where(mapping_type: filters.mapping_type)
    end
  end
end
