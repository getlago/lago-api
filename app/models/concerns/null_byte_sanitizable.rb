# frozen_string_literal: true

# Strips PostgreSQL-incompatible NULL bytes from string attributes.
#
# Postgres text/varchar columns cannot store a NULL byte. When one reaches the
# adapter on write it raises ArgumentError (string contains null byte), which
# surfaces to the API as an unhandled 500. Normalizing the value on assignment
# turns that crash into clean, stored data.
#
# Usage:
#
#   class Customer < ApplicationRecord
#     include NullByteSanitizable
#
#     sanitize_null_bytes :name, :firstname, :lastname
#     sanitize_null_bytes(*ADDRESS_FIELDS, blank_to_nil: true)
#   end
#
# blank_to_nil: when true, a value that is empty after stripping becomes nil
# (preserves the historical behavior of the address-field normalizer).
module NullByteSanitizable
  extend ActiveSupport::Concern

  NULL_BYTE = "\u0000"

  class_methods do
    def sanitize_null_bytes(*attributes, blank_to_nil: false)
      attributes.flatten.each do |attribute|
        normalizes attribute, with: ->(value) do
          cleaned = value.delete(NULL_BYTE)
          blank_to_nil ? cleaned.presence : cleaned
        end
      end
    end
  end
end
