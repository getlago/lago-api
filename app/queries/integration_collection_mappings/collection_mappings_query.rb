# frozen_string_literal: true

module IntegrationCollectionMappings
  class CollectionMappingsQuery < BaseQuery
    def call
      integration_collection_mappings = paginate(base_scope)
      integration_collection_mappings = integration_collection_mappings.order(created_at: :desc)

      integration_collection_mappings = with_integration_id(integration_collection_mappings) if filters.integration_id
      integration_collection_mappings = with_mapping_type(integration_collection_mappings) if filters.mapping_type

      result.integration_collection_mappings = integration_collection_mappings
      result
    end

    private

    def base_scope
      ::IntegrationCollectionMappings::BaseCollectionMapping
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
