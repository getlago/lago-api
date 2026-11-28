# frozen_string_literal: true

module Entitlement
  module Concerns
    # Builds the failures of a write of an entitlements map where they happen, with the path of the failing entry of
    # the request (entitlements.<feature>[.<privilege>]), which native v2 renders as the field. The failures keep the
    # keys that v1 and GraphQL clients read. The service declares `failed_field` on its result.
    module EntryPathConcern
      extend ActiveSupport::Concern

      private

      # failed_field lets the v2 controller render an unknown feature or privilege on its path.
      def not_found_at!(path, resource)
        result.failed_field = path
        result.not_found_failure!(resource:).raise_if_error!
      end

      # The privilege values of a feature are a map of privilege codes to values, or empty for none.
      def validate_privilege_values_shape!(path, privilege_values)
        return if privilege_values.blank? || privilege_values.is_a?(Hash)

        result.single_validation_failure!(field: path, error_code: "value_is_invalid").raise_if_error!
      end

      # An invalid entitlement value saved in the block fails on path; v1 and GraphQL clients read privilege.<attribute>.
      def save_value_at!(path)
        yield
      rescue ActiveRecord::RecordInvalid => e
        raise unless e.record.is_a?(EntitlementValue)

        raise entitlement_value_failure(e.record, path)
      end

      def entitlement_value_failure(entitlement_value, path)
        failure = BaseService::ValidationFailure.from_errors(result, entitlement_value.errors)
        at_path = ->(field) { (field.to_sym == :value) ? path : :"privilege.#{field}" }

        BaseService::ValidationFailure.new(
          result,
          messages: failure.messages.transform_keys { :"privilege.#{it}" },
          codes: failure.codes.transform_keys(&at_path),
          meta: failure.meta.transform_keys(&at_path)
        )
      end
    end
  end
end
