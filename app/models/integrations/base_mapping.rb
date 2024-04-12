# frozen_string_literal: true

module Integrations
  class BaseMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'
    belongs_to :mappable, polymorphic: true
  end
end
