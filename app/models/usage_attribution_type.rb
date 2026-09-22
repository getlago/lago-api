# frozen_string_literal: true

class UsageAttributionType < ApplicationRecord
  include Discard::Model

  self.discard_column = :deleted_at

  ROLES = {
    hierarchical: "hierarchical",
    flat: "flat"
  }.freeze

  MAX_ATTRIBUTION_KEYS = 4

  belongs_to :organization
  belongs_to :parent, -> { with_discarded }, class_name: "UsageAttributionType", optional: true
  has_many :children, class_name: "UsageAttributionType", foreign_key: :parent_id, inverse_of: :parent
  has_many :usage_attribution_values

  enum :role, ROLES, validate: true

  normalizes :attribution_keys, with: ->(attribution_keys) do
    Array(attribution_keys).filter_map { it.to_s.strip.presence }.uniq
  end

  validates :code, presence: true, length: {maximum: 255}, uniqueness: {scope: :organization_id, conditions: -> { where(deleted_at: nil) }}
  validates :name, length: {maximum: 255}
  validates :attribution_keys, presence: true, length: {maximum: MAX_ATTRIBUTION_KEYS}

  validate :validate_attribution_keys
  validate :validate_parent

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[code name]
  end

  private

  def validate_attribution_keys
    return if attribution_keys.blank?

    errors.add(:attribution_keys, :too_long) if attribution_keys.any? { it.length > 255 }
    errors.add(:attribution_keys, :taken) if claimed_by_another_type?
  end

  def claimed_by_another_type?
    scope = self.class.where(organization_id:).where("attribution_keys && ARRAY[?]::varchar[]", attribution_keys)
    scope = scope.where.not(id:) if persisted?
    scope.exists?
  end

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
#  id               :uuid             not null, primary key
#  attribution_keys :string           default([]), not null, is an Array
#  code             :string           not null
#  deleted_at       :datetime
#  name             :string
#  role             :enum             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :uuid             not null
#  parent_id        :uuid
#
# Indexes
#
#  index_usage_attribution_types_on_organization_id           (organization_id)
#  index_usage_attribution_types_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_usage_attribution_types_on_parent_id                 (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (parent_id => usage_attribution_types.id)
#
