# frozen_string_literal: true

module Sources
  class IntegrationMappingsByMappable < GraphQL::Dataloader::Source
    def initialize(integration_id = nil)
      @integration_id = integration_id
    end

    def fetch(mappables)
      mappings = IntegrationMappings::BaseMapping.where(mappable: mappables)
      mappings = mappings.where(integration_id: @integration_id) if @integration_id
      mappings_by_mappable = mappings.group_by { [it.mappable_type, it.mappable_id] }

      mappables.map do |mappable|
        mappings_by_mappable.fetch([mappable.class.polymorphic_name, mappable.id], [])
      end
    end
  end
end
