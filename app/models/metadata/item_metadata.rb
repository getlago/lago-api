# frozen_string_literal: true

module Metadata
  class ItemMetadata < ApplicationRecord
    belongs_to :organization
    belongs_to :owner, polymorphic: true

    validates :owner_id, uniqueness: {scope: :owner_type}
    validates :value, exclusion: {in: [nil], message: :blank}
    validate :value_correctness
    validate :owner_consistency

    private

    def value_correctness
      return if value.blank?

      unless value.is_a?(Hash)
        errors.add(:value, "must be a Hash")
        return
      end

      if value.size > 50
        errors.add(:value, "cannot have more than 50 keys")
      end

      value.each do |key, val|
        unless key.is_a?(String) && key.length <= 40
          errors.add(:value, "key '#{key}' must be a String up to 40 characters")
        end

        if val.present? && !(val.is_a?(String) && val.length <= 255)
          errors.add(:value, "value for key '#{key}' must be empty or a String up to 255 characters")
        end
      end
    end

    def owner_consistency
      return if owner.blank?

      if owner.organization_id != organization_id
        errors.add(:owner, "must belong to the same organization as the metadata")
      end
    end
  end
end

# == Schema Information
#
# Table name: item_metadata
#
#  id                                             :uuid             not null, primary key
#  owner_type(Polymorphic owner type)             :string           not null
#  value(item_metadata key-value pairs)           :jsonb            not null
#  created_at                                     :datetime         not null
#  updated_at                                     :datetime         not null
#  organization_id(Reference to the organization) :uuid             not null
#  owner_id(Polymorphic owner id)                 :uuid             not null
#
# Indexes
#
#  index_item_metadata_for_fk                      (id,owner_id,organization_id) UNIQUE
#  index_item_metadata_on_organization_id          (organization_id)
#  index_item_metadata_on_owner_type_and_owner_id  (owner_type,owner_id) UNIQUE
#  index_item_metadata_on_value                    (value) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => cascade
#
