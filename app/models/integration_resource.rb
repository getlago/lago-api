# frozen_string_literal: true

class IntegrationResource < ApplicationRecord
  belongs_to :syncable, polymorphic: true
  belongs_to :integration, class_name: 'Integrations::BaseIntegration'

  RESOURCE_TYPES = %i[invoice sales_order payment credit_note].freeze

  enum resource_type: RESOURCE_TYPES
end

# == Schema Information
#
# Table name: integration_resources
#
#  id             :uuid             not null, primary key
#  resource_type  :integer          default("invoice"), not null
#  syncable_type  :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  external_id    :string
#  integration_id :uuid
#  syncable_id    :uuid             not null
#
# Indexes
#
#  index_integration_resources_on_integration_id  (integration_id)
#  index_integration_resources_on_syncable        (syncable_type,syncable_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_id => integrations.id)
#
