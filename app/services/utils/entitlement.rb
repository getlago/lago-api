# frozen_string_literal: true

module Utils
  class Entitlement
    # Codes are saved stripped. A code that is not a string is left to the model validation.
    def self.stripped_code(code)
      code.is_a?(String) ? code.strip : code
    end

    # A hash that strong params kept (a single object, numeric keys) is refused; a blank one is ignored as before.
    def self.privileges_param_invalid?(privileges_params)
      privileges_params.present? && !privileges_params.is_a?(Array)
    end

    # Two codes are duplicates when they are equal once stripped, as they reach the same privilege.
    def self.privilege_code_is_duplicated?(privileges_params)
      return false if privileges_params.blank?

      seen = Set.new
      privileges_params.any? { !seen.add?(stripped_code(it[:code])) }
    end

    def self.cast_value(value, type)
      return nil if value.nil?

      case type
      when "integer"
        value.to_i
      when "boolean"
        ActiveModel::Type::Boolean.new.cast(value)
      else
        value
      end
    end

    def self.same_value?(type, value1, value2)
      cast_value(value1, type) == cast_value(value2, type)
    end

    def self.convert_gql_input_to_params(entitlements)
      Array.wrap(entitlements).map do |ent|
        [
          ent.feature_code,
          ent.privileges&.map { [it.privilege_code, it.value] }.to_h
        ]
      end.to_h
    end
  end
end
