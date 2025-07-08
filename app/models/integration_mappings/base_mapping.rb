# frozen_string_literal: true

module IntegrationMappings
  class BaseMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = "integration_mappings"

    belongs_to :integration, class_name: "Integrations::BaseIntegration"
    belongs_to :mappable, polymorphic: true
    belongs_to :organization

    MAPPABLE_TYPES = %i[AddOn BillableMetric].freeze

    settings_accessors :external_id, :external_account_code, :external_name
  end
end

# == Schema Information
#
# Table name: integration_mappings
#
#  id              :uuid             not null, primary key
#  mappable_type   :string           not null
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  integration_id  :uuid             not null
#  mappable_id     :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_integration_mappings_on_integration_id   (integration_id)
#  index_integration_mappings_on_mappable         (mappable_type,mappable_id)
#  index_integration_mappings_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#  fk_rails_...  (organization_id => organizations.id)
#
