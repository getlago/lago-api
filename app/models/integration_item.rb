# frozen_string_literal: true

class IntegrationItem < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :integration, class_name: "Integrations::BaseIntegration"

  ITEM_TYPES = [
    :standard,
    :tax,
    :account
  ].freeze

  enum :item_type, ITEM_TYPES

  validates :external_id, presence: true, uniqueness: {scope: %i[integration_id item_type]}

  def self.ransackable_attributes(_auth_object = nil)
    %w[external_account_code external_id external_name]
  end
end

# == Schema Information
#
# Table name: integration_items
#
#  id                    :uuid             not null, primary key
#  integration_id        :uuid             not null
#  item_type             :integer          not null
#  external_id           :string           not null
#  external_account_code :string
#  external_name         :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_int_items_on_external_id_and_int_id_and_type  (external_id,integration_id,item_type) UNIQUE
#  index_integration_items_on_integration_id           (integration_id)
#
