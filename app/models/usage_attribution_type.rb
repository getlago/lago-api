# frozen_string_literal: true

class UsageAttributionType < ApplicationRecord
  include Discard::Model

  self.discard_column = :deleted_at

  ROLES = {
    hierarchical: "hierarchical",
    flat: "flat"
  }.freeze

  belongs_to :organization
  belongs_to :parent, -> { with_discarded }, class_name: "UsageAttributionType", optional: true
  has_many :children, class_name: "UsageAttributionType", foreign_key: :parent_id, inverse_of: :parent
  has_many :usage_attribution_values

  enum :role, ROLES, validate: true

  validates :code, presence: true, length: {maximum: 255}, uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}
  validates :name, length: {maximum: 255}
  validates :attribution_key, presence: true, length: {maximum: 255}, uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}

  validate :validate_parent

  default_scope -> { kept }

  private

  def validate_parent
    return if parent.nil?

    if flat?
      errors.add(:parent_id, :forbidden_for_flat_role)
      return
    end

    errors.add(:parent_id, :must_be_hierarchical) unless parent.hierarchical?
    errors.add(:parent_id, :must_belong_to_same_organization) unless parent.organization_id == organization_id
    errors.add(:parent_id, :cannot_form_a_cycle) if cycle_through?(parent)
  end

  def cycle_through?(node)
    visited = []

    while node && visited.exclude?(node)
      return true if node.id == id

      visited << node
      node = node.parent
    end

    false
  end
end

# == Schema Information
#
# Table name: usage_attribution_types
# Database name: primary
#
#  id              :uuid             not null, primary key
#  attribution_key :string           not null
#  code            :string           not null
#  deleted_at      :datetime
#  name            :string
#  role            :enum             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  parent_id       :uuid
#
# Indexes
#
#  index_usage_attribution_types_on_organization_id           (organization_id)
#  index_usage_attribution_types_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_usage_attribution_types_on_organization_id_and_key   (organization_id,attribution_key) UNIQUE WHERE (deleted_at IS NULL)
#  index_usage_attribution_types_on_parent_id                 (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (parent_id => usage_attribution_types.id)
#
