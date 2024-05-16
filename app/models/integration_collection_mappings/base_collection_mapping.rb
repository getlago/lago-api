# frozen_string_literal: true

module IntegrationCollectionMappings
  class BaseCollectionMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_collection_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'

    MAPPING_TYPES = %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit credit_note].freeze

    enum mapping_type: MAPPING_TYPES

    validates :mapping_type, uniqueness: {scope: :integration_id}

    settings_accessors :external_id, :external_account_code, :external_name
  end
end
