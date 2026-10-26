# frozen_string_literal: true

module Api
  # The error body of the native v2 controllers:
  #
  #   {code: "validation_errors", details: [{code: "value_is_mandatory", field: "name", meta: {}}]}
  #
  # It overrides the renderers of ApiErrors and ApiResponses, which v1, Admin and the data API keep,
  # so that every caller renders it, the callbacks of Api::BaseController and render_error_response
  # included. The status is the HTTP one only. `details` is always an array and `meta` always an
  # object, so that a client never checks for nil.
  module V2Errors
    extend ActiveSupport::Concern

    # The v1 message is the reason phrase, which the v2 body leaves out.
    def unauthorized_error(**) = render_v2_error(401, code: "unauthorized")

    def forbidden_error(code:) = render_v2_error(403, code:)

    def not_found_error(resource:) = render_v2_error(404, code: "#{resource}_not_found")

    # A record whose state refuses the action, a 422 like the catalog's own refusals. The v1 405
    # would need an Allow header, and the method is supported.
    def method_not_allowed_error(code:) = render_v2_error(422, code:)

    def lock_acquisition_error(code:) = render_v2_error(422, code:)

    # One entry per code of ValidationFailure#messages, in order and duplicates kept, so that
    # grouping the entries by field gives the hash back.
    def validation_errors(errors:)
      details = errors.flat_map do |field, codes|
        Array.wrap(codes).map { error_detail(code: it, field:) }
      end

      render_v2_error(422, code: "validation_errors", details:)
    end

    private

    # A 400 keyed by the offending parameter, `{param => {reason:, **meta}}`. Without a reason, the
    # code of the error is the code of its entry.
    def invalid_request_error(code:, error_details:)
      details = error_details.map do |param, detail|
        error_detail(code: detail.fetch(:reason, code), field: param, meta: detail.except(:reason))
      end

      render_v2_error(400, code:, details:)
    end

    def error_detail(code:, field:, meta: {})
      {code:, field: field.to_s, meta:}
    end

    def render_v2_error(status, code:, details: [])
      render(json: {code:, details:}, status:)
    end
  end
end
