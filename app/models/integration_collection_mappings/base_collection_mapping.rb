# frozen_string_literal: true

module IntegrationCollectionMappings
  class BaseCollectionMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_collection_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'

    MAPPING_TYPES = descendants.map do |descendant|
      descendant.const_get(:MAPPING_TYPES)&.to_sym
    end.uniq.freeze
  end
end
