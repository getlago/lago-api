# frozen_string_literal: true

module IntegrationCollectionMappings
  class BaseCollectionMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = "integration_collection_mappings"

    belongs_to :integration, class_name: "Integrations::BaseIntegration"
    belongs_to :organization

    MAPPING_TYPES = %i[
      fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit credit_note account
    ].freeze

    enum :mapping_type, MAPPING_TYPES

    validates :mapping_type, uniqueness: {scope: :integration_id}

    settings_accessors :external_id, :external_account_code, :external_name
  end
end

# == Schema Information
#
# Table name: integration_collection_mappings
#
#  id              :uuid             not null, primary key
#  mapping_type    :integer          not null
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  integration_id  :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_int_collection_mappings_on_mapping_type_and_int_id  (mapping_type,integration_id) UNIQUE
#  index_integration_collection_mappings_on_integration_id   (integration_id)
#  index_integration_collection_mappings_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#  fk_rails_...  (organization_id => organizations.id)
#
