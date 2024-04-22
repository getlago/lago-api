# frozen_string_literal: true

class IntegrationItem < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :integration, class_name: 'Integrations::BaseIntegration'

  ITEM_TYPES = [
    :standard,
    :tax,
  ].freeze

  enum item_type: ITEM_TYPES

  validates :external_id, presence: true
end
