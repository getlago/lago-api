# frozen_string_literal: true

module Entitlement
  module Concerns
    module CreateOrUpdateConcern
      extend ActiveSupport::Concern

      def validate_value(value, privilege)
        return value if value.nil?

        if privilege.value_type == "select"
          unless privilege.config.dig("select_options").include?(value)
            raise BaseService::ValidationFailure.new(result, messages: {"#{privilege.code}_privilege_value": ["value_not_in_select_options"]})
          end
        end

        return value if privilege.value_type == "boolean" && [true, false].include?(value)
        return value if privilege.value_type == "integer" && value.is_a?(Integer)
        return value if privilege.value_type == "string" && value.is_a?(String)

        raise BaseService::ValidationFailure.new(result, messages: {"#{privilege.code}_privilege_value": ["value_is_invalid"]})
      end
    end
  end
end
