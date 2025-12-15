# frozen_string_literal: true

class Role < ApplicationRecord
  include Discard::Model

  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :organization, optional: true
  has_many :membership_roles

  scope :admins, -> { where(admin: true) }
  scope :with_names, ->(*names) { where("LOWER(name) IN (?)", names.map(&:downcase)) }
  scope :with_organization, ->(organization_id) { where(organization_id: [nil, organization_id]) }

  # Only communicate to the user about his choices
  validate :name_is_not_reserved
  validates :name,
    presence: true,
    uniqueness: {case_sensitive: false, conditions: -> { where(deleted_at: nil) }, scope: :organization_id},
    if: -> { organization_id && deleted_at.blank? }
  validates :name, length: {maximum: 100, allow_blank: true}
  validates :description, length: {maximum: 255, allow_blank: true}
  validates :permissions, presence: true, if: :organization_id

  private

  RESERVED_NAMES = %w[admin finance manager].freeze

  def name_is_not_reserved
    errors.add(:name, :taken) if RESERVED_NAMES.include?(name&.downcase)
  end
end

# == Schema Information
#
# Table name: roles
# Database name: primary
#
#  id              :uuid             not null, primary key
#  admin           :boolean          default(FALSE), not null
#  deleted_at      :datetime
#  description     :text
#  name            :string           not null
#  permissions     :text             default([]), not null, is an Array
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid
#
# Indexes
#
#  index_roles_by_name_per_organization  (organization_id NULLS FIRST, lower((name)::text)) UNIQUE WHERE (deleted_at IS NULL)
#  index_roles_by_unique_admin           (admin) UNIQUE WHERE (admin AND (deleted_at IS NULL))
#  index_roles_on_organization_id        (organization_id)
#
