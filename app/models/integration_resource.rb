# frozen_string_literal: true

class IntegrationResource < ApplicationRecord
  belongs_to :syncable, polymorphic: true
  belongs_to :integration, class_name: 'Integrations::BaseIntegration'

  RESOURCE_TYPES = %i[invoice sales_order payment credit_note].freeze

  enum resource_type: RESOURCE_TYPES
end
