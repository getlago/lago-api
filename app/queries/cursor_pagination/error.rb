# frozen_string_literal: true

module CursorPagination
  # Raised while reading the pagination parameters of a request, before any SQL runs.
  # `details` is keyed by the offending parameter, and rendered as `error_details`.
  class Error < StandardError
    INVALID_CURSOR = "invalid_pagination_cursor"
    CURSOR_EXPIRED = "pagination_cursor_expired"

    attr_reader :code, :details

    def initialize(code:, details:)
      @code = code
      @details = details

      super("#{code}: #{details.keys.join(", ")}")
    end
  end
end
