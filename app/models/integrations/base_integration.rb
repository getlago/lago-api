# frozen_string_literal: true

module Integrations
  class BaseIntegration < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable

    self.table_name = 'integrations'

    belongs_to :organization

    has_many :integration_items, dependent: :destroy, foreign_key: :integration_id
    has_many :integration_mappings,
      class_name: 'IntegrationMappings::BaseMapping',
      foreign_key: :integration_id,
      dependent: :destroy
    has_many :integration_collection_mappings,
      class_name: 'IntegrationCollectionMappings::BaseCollectionMapping',
      foreign_key: :integration_id,
      dependent: :destroy

    validates :code, uniqueness: {scope: :organization_id}
    validates :name, presence: true

    def self.integration_type(type)
      case type
      when 'netsuite'
        'Integrations::NetsuiteIntegration'
      else
        raise(NotImplementedError)
      end
    end
  end
end
