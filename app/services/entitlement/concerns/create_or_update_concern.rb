# frozen_string_literal: true

module Entitlement
  module Concerns
    module CreateOrUpdateConcern
      extend ActiveSupport::Concern

      def validate_value(value, privilege)
        return value if value.nil?

        if privilege.value_type == "select"
          if privilege.config.dig("select_options").include?(value)
            return value
          end

          raise value_failure(privilege, "value_not_in_select_options", allowed_values: privilege.config["select_options"].map(&:to_s))
        end

        if privilege.value_type == "boolean" && [true, false, "true", "false"].include?(value)
          return value
        end

        if privilege.value_type == "integer"
          return value if value.is_a?(Integer)
          return value if value.is_a?(String) && value.to_i.to_s == value
        end
        return value if privilege.value_type == "string" && value.is_a?(String)

        raise value_failure(privilege, "value_is_invalid")
      end

      private

      # v1 and GraphQL clients read <privilege>_privilege_value.
      def value_failure(privilege, code, **meta)
        field = :"#{privilege.code}_privilege_value"

        BaseService::ValidationFailure.new(
          result,
          messages: {field => [code]},
          codes: {field => [code]},
          meta: {field => meta}.compact_blank
        )
      end
    end
  end
end
