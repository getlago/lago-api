# frozen_string_literal: true

module Utils
  class Entitlement
    def self.cast_value(value, type)
      return nil if value.blank?

      case type
      when "integer"
        value.to_i
      when "boolean"
        ActiveModel::Type::Boolean.new.cast(value)
      else
        value
      end
    end
  end
end
