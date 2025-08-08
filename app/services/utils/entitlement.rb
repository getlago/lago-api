# frozen_string_literal: true

module Utils
  class Entitlement
    def self.privilege_code_is_duplicated?(privileges_params)
      return false if privileges_params.blank?

      seen = Set.new
      privileges_params.any? { !seen.add?(it[:code]) }
    end

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

    def self.convert_gql_input_to_params(entitlements)
      entitlements.map do |ent|
        [
          ent.feature_code,
          ent.privileges&.map { [it.privilege_code, it.value] }.to_h
        ]
      end.to_h
    end
  end
end
