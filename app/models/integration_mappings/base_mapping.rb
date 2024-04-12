# frozen_string_literal: true

module IntegrationMappings
  class BaseMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'
    belongs_to :mappable, polymorphic: true

    MAPPABLE_TYPES = descendants.map do |descendant|
      descendant.const_get(:MAPPABLE_TYPES)&.to_sym
    end.uniq.freeze
  end
end
