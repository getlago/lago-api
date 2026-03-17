# frozen_string_literal: true

class GroupKey < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  KEY_TYPES = {pricing: "pricing", presentation: "presentation"}.freeze

  belongs_to :organization
  belongs_to :charge
  belongs_to :charge_filter, optional: true

  enum :key_type, KEY_TYPES

  default_scope -> { kept }

  validates :key, presence: true
  validates :key_type, presence: true
end

# == Schema Information
#
# Table name: group_keys
# Database name: primary
#
#  id               :uuid             not null, primary key
#  deleted_at       :datetime
#  key              :string           not null
#  key_type         :enum             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  charge_filter_id :uuid
#  charge_id        :uuid             not null
#  organization_id  :uuid             not null
#
# Indexes
#
#  index_group_keys_on_charge_filter_id           (charge_filter_id)
#  index_group_keys_on_charge_filter_id_not_null  (charge_filter_id) WHERE (charge_filter_id IS NOT NULL)
#  index_group_keys_on_charge_id                  (charge_id)
#  index_group_keys_on_deleted_at                 (deleted_at)
#  index_group_keys_on_organization_id            (organization_id)
#  index_group_keys_unique_active                 (charge_id,charge_filter_id,key,key_type) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (charge_filter_id => charge_filters.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#
