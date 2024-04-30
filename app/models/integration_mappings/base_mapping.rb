# frozen_string_literal: true

module IntegrationMappings
  class BaseMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'
    belongs_to :mappable, polymorphic: true

    MAPPABLE_TYPES = %i[AddOn BillableMetric].freeze

    settings_accessors :external_id, :external_account_code, :external_name
  end
end
