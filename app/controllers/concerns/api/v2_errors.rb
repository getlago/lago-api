# frozen_string_literal: true

module Api
  # The error body of the native v2 controllers:
  #
  #   {code: "validation_errors", details: [{code: "value_is_mandatory", field: "name", meta: {}}]}
  #
  # It defines the renderers of Api::V1Errors, which only v1, Admin and the data API include, under
  # the same names, so that the callbacks Api::BaseController shares with v1 render it too, and it
  # overrides ApiResponses#not_found_error. bad_request_error aside: Api::V2::BaseController rescues
  # a missing parameter itself. The status is the HTTP one only. `details` is always an array and
  # `meta` always an object, so that a client never checks for nil.
  module V2Errors
    extend ActiveSupport::Concern

    # The v1 message is the reason phrase, which the v2 body leaves out.
    def unauthorized_error = render_v2_error(401, code: "unauthorized")

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

    # The provider failures name their provider, not its message: a sentence of the provider's, which
    # can echo the request.
    def provider_error(provider, _error)
      render_provider_error(422, code: "provider_error", meta: {provider_code: provider.code})
    end

    def thirdpary_error(error:)
      render_provider_error(422, code: "third_party_error", meta: {third_party: error.third_party})
    end

    def too_many_provider_requests_error(error:)
      render_provider_error(429, code: "too_many_provider_requests", meta: {provider_name: error.provider_name})
    end

    def render_error_response(error_result)
      error = error_result.error

      case error
      when BaseService::NotFoundFailure then not_found_error(resource: error.resource)
      when BaseService::MethodNotAllowedFailure then method_not_allowed_error(code: error.code)
      when BaseService::ValidationFailure then validation_errors(errors: error.messages)
      when BaseService::ForbiddenFailure then forbidden_error(code: error.code)
      # Only payment providers fail with it today, refusing the organization's own credentials: the
      # API key of the request is fine, which the code of unauthorized_error would deny.
      when BaseService::UnauthorizedFailure then render_v2_error(401, code: "provider_unauthorized")
      when BaseService::ProviderFailure then provider_error(error.provider, error.original_error)
      when BaseService::TooManyProviderRequestsFailure then too_many_provider_requests_error(error:)
      when BaseService::ThirdPartyFailure then thirdpary_error(error:)
      when BaseService::LockAcquisitionFailure then lock_acquisition_error(code: error.code)
      else raise(error)
      end
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

    def render_provider_error(status, code:, meta:)
      render_v2_error(status, code:, details: [error_detail(code:, field: :base, meta:)])
    end

    def error_detail(code:, field:, meta: {})
      {code:, field: field.to_s, meta:}
    end

    def render_v2_error(status, code:, details: [])
      render(json: {code:, details:}, status:)
    end
  end
end
