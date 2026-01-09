# frozen_string_literal: true

module Metadata
  class ItemMetadata < ApplicationRecord
    MAX_NUMBER_OF_KEYS = 50
    MAX_KEY_LENGTH = 50
    MAX_VALUE_LENGTH = 255
    MAX_INNER_HASH_SIZE = 500

    belongs_to :organization
    belongs_to :owner, polymorphic: true

    validates :value, exclusion: {in: [nil], message: :blank}
    validate :value_correctness

    private

    def value_correctness
      return if value.blank?

      unless value.is_a?(Hash)
        errors.add(:value, "must be a Hash")
        return
      end

      if value.size > MAX_NUMBER_OF_KEYS
        errors.add(:value, "cannot have more than #{MAX_NUMBER_OF_KEYS} keys")
      end

      value.each do |key, val|
        unless key.is_a?(String) && key.length <= MAX_KEY_LENGTH
          errors.add(:value, "key '#{key}' must be a String up to #{MAX_KEY_LENGTH} characters")
        end

        next if value.nil?

        # Metadata was implemented with very strict limits to prevent abuse, when making it flexible, we're adding some of these limits too
        case val.class.name
        when "String"
          next if val.length <= MAX_VALUE_LENGTH

          errors.add(:value, "value for key '#{key}' must be up to #{MAX_VALUE_LENGTH} characters")
        when "Hash"
          if val.size > MAX_NUMBER_OF_KEYS
            errors.add(:value, "value for key '#{key}' cannot have more than #{MAX_NUMBER_OF_KEYS} keys")
          end

          # validation: hashes inside the main object cannot be bigger than 500 characters
          next if val.values.all? { |v| [String, Array, Hash].include?(v.class) && v.to_json.size <= MAX_INNER_HASH_SIZE }
          errors.add(:value, "all values in hash for key '#{key}' must have max json size of #{MAX_INNER_HASH_SIZE} characters")
        when "Array"
          if val.size > MAX_NUMBER_OF_KEYS
            errors.add(:value, "value for key '#{key}' cannot have more than #{MAX_NUMBER_OF_KEYS} items")
          end
        end
      end
    end
  end
end

# == Schema Information
#
# Table name: item_metadata
# Database name: primary
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
#  index_item_metadata_on_organization_id          (organization_id)
#  index_item_metadata_on_owner_type_and_owner_id  (owner_type,owner_id) UNIQUE
#  index_item_metadata_on_value                    (value) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => cascade
#
