# frozen_string_literal: true

module Api
  module V1
    # Parent of every v1 controller, for the behaviour only v1 paths share.
    class BaseController < Api::BaseController
      # A controller sets `self.max_page_size = n` to cap its own per_page below the organization
      # or global limit.
      # rubocop:disable ThreadSafety/ClassAndModuleAttributes
      class_attribute :max_page_size, instance_writer: false
      # rubocop:enable ThreadSafety/ClassAndModuleAttributes

      before_action :validate_pagination_params, if: :api_v1_request?

      private

      # Keyed on the path rather than the controller: the /api/v2 fallback routes serve the same
      # v1 controllers and keep accepting any page size.
      def api_v1_request?
        request.path.start_with?("/api/v1/")
      end

      def validate_pagination_params
        errors = {
          page: pagination_param_error(:page, max: nil),
          per_page: pagination_param_error(:per_page, max: max_per_page)
        }.compact

        validation_errors(errors:) if errors.any?
      end

      # A blank value is treated as absent. Only plain positive decimals are valid: Integer() would also
      # accept forms such as 010, +5, 1_000 or a leading space.
      def pagination_param_error(name, max:)
        return if params[name].blank?

        value = params[name].to_s
        if value.match?(/\A[1-9]\d*\z/) && (max.nil? || value.to_i <= max)
          nil
        else
          ["value_is_out_of_range"]
        end
      end

      # The effective per_page limit of the controller: its own cap, if any, within the
      # organization or global limit.
      def max_per_page
        [self.class.max_page_size, current_organization.pagination_max_page_size || Pagination.max_per_page].compact.min
      end
    end
  end
end
