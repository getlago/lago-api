# frozen_string_literal: true

module Metadata
  class ItemMetadata < ApplicationRecord
    MAX_NUMBER_OF_KEYS = 50
    MAX_KEY_LENGTH = 100
    MAX_VALUE_LENGTH = 255

    belongs_to :organization
    belongs_to :owner, polymorphic: true

    validates :value, exclusion: {in: [nil], message: :blank}
    validate :value_correctness

    private

    # The sentences, which v1 and GraphQL clients read, carry the token of their error as `code`, and the
    # key of the value they refuse as `key` (see Metadata::UpdateItemService.validation_failure).
    def value_correctness
      return if value.blank?

      unless value.is_a?(Hash)
        errors.add(:value, "must be a Hash", code: "invalid_type")
        return
      end

      if value.size > MAX_NUMBER_OF_KEYS
        errors.add(:value, "cannot have more than #{MAX_NUMBER_OF_KEYS} keys", code: "too_many_keys")
      end

      value.each do |key, val|
        unless key.is_a?(String) && key.length <= MAX_KEY_LENGTH
          code = key.is_a?(String) ? "key_too_long" : "invalid_type"
          errors.add(:value, "key '#{key}' must be a String up to #{MAX_KEY_LENGTH} characters", code:)
        end

        valid_value = val.nil? || (val.is_a?(String) && val.length <= MAX_VALUE_LENGTH)
        unless valid_value
          errors.add(:value, "value for key '#{key}' must be empty or a String up to #{MAX_VALUE_LENGTH} characters", code: value_code(val), key:)
        end
      end
    end

    def value_code(val)
      if val.is_a?(String)
        "value_too_long"
      elsif val.is_a?(Hash) || val.is_a?(Array)
        "nested_structure_not_allowed"
      else
        "invalid_type"
      end
    end
  end
end

# == Schema Information
#
# Table name: item_metadata
# Database name: primary
#
#  id              :uuid             not null, primary key
#  owner_type      :string           not null
#  value           :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  owner_id        :uuid             not null
#
# Indexes
#
#  index_item_metadata_on_organization_id          (organization_id)
#  index_item_metadata_on_owner_type_and_owner_id  (owner_type,owner_id) UNIQUE
#  index_item_metadata_on_value                    (value) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => cascade
#
