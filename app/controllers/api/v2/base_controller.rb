# frozen_string_literal: true

module Api
  module V2
    # Parent of the native v2 controllers, for the behaviour they share and v1 does not.
    class BaseController < Api::BaseController
      # Every native v2 endpoint belongs to the product catalog. Included ahead of the cursor
      # callback, so that a disabled catalog is a 403 before any pagination parameter is read.
      include Api::RequiresProductCatalog
      # Right after the catalog check, so that an invalid `expand` is a 400 on every action,
      # before any pagination parameter is read and before any lookup.
      include Api::Expandable

      rescue_from ActionController::ParameterMissing, with: :missing_parameter_error
      rescue_from ::CursorPagination::Error, with: :pagination_error

      # Registered here, not by `cursor_paginated_index`: it then runs after authentication,
      # authorization and the catalog check, and before every callback of the controllers
      # whatever their order, so that an invalid pagination parameter is a 400 before any
      # lookup.
      before_action :read_cursor, if: :cursor_paginated_index?

      # Declares the index of the controller as cursor paginated, on `model` under `sort`.
      def self.cursor_paginated_index(model, sort: ::CursorPagination::DEFAULT_SORT)
        private(define_method(:paginated_model) { model })
        private(define_method(:paginated_sort) { sort })
      end

      private

      attr_reader :cursor

      def cursor_paginated_index?
        action_name == "index" && respond_to?(:paginated_model, true)
      end

      def read_cursor
        @cursor = cursor_pagination(paginated_model, sort: paginated_sort)
      end

      def cursor_pagination(model, sort: ::CursorPagination::DEFAULT_SORT)
        ::CursorPagination::Cursor.from_params(params, table: model.table_name, sort:)
      end

      # For a list returned whole: it still rejects `page` and `per_page`, which a
      # client paging until an empty page would otherwise send forever.
      def reject_offset_pagination!
        ::CursorPagination::Cursor.reject_offset_params!(params, reason: "not_paginated")
      end

      def missing_parameter_error(error)
        invalid_request_error(code: "missing_parameter", error_details: {error.param => {reason: "missing"}})
      end

      def pagination_error(error)
        Yabeda.api_pagination.errors_total.increment({code: error.code})
        invalid_request_error(code: error.code, error_details: error.details)
      end

      # Every v2 400 shares this body, keyed by the offending parameter.
      def invalid_request_error(code:, error_details:)
        render(
          json: {
            status: 400,
            error: "Bad Request",
            code:,
            error_details:
          },
          status: :bad_request
        )
      end
    end
  end
end
