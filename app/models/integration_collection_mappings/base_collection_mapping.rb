# frozen_string_literal: true

module IntegrationCollectionMappings
  class BaseCollectionMapping < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_collection_mappings'

    belongs_to :integration, class_name: 'Integrations::BaseIntegration'

    MAPPING_TYPES = %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].freeze

    enum mapping_type: MAPPING_TYPES

    validates :mapping_type, uniqueness: { scope: :integration_id }
  end
end
