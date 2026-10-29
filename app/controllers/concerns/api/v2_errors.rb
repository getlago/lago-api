# frozen_string_literal: true

module Api
  # The error body of the native v2 controllers:
  #
  #   {code: "validation_errors", details: [{code: "value_is_mandatory", field: "name", meta: {}}]}
  #
  # It defines the Api::V1Errors renderers that the callbacks Api::BaseController shares with v1
  # call, under the same names, so that they render it too, and it overrides
  # ApiResponses#not_found_error. The other failures only render_error_response renders, and
  # Api::V2::BaseController rescues a missing parameter itself. The status is the HTTP one only.
  # `details` is always an array and `meta` always an object, so that a client never checks for nil.
  module V2Errors
    extend ActiveSupport::Concern

    # A Lago error code, which a client switches on.
    TOKEN = /\A[a-z][a-z0-9_]*\z/

    # The v1 message is the reason phrase, which the v2 body leaves out.
    def unauthorized_error = render_v2_error(401, code: "unauthorized")

    def forbidden_error(code:) = render_v2_error(403, code:)

    # One code for every resource, named in its meta: a request can miss more than one record.
    def not_found_error(resource:)
      render_v2_error(404, code: "resource_not_found", details: [error_detail(code: "resource_not_found", field: :base, meta: {resource:})])
    end

    def validation_errors(errors:)
      render_validation_entries(BaseService::ValidationFailure.entries_from(errors))
    end

    def render_error_response(error_result)
      error = error_result.error

      case error
      when BaseService::NotFoundFailure then not_found_error(resource: error.resource)
      # A record whose state refuses the action, a 422 like the catalog's own refusals. The v1 405
      # would need an Allow header, and the method is supported.
      when BaseService::MethodNotAllowedFailure then render_v2_error(422, code: error.code)
      # Ahead of ValidationFailure, its parent: its messages are the sentences of the contract.
      when BaseQuery::FiltersFailure then filter_errors(error.filters)
      # Its entries, which carry the meta that its messages alone would drop.
      when BaseService::ValidationFailure then render_validation_entries(error.entries)
      when BaseService::ForbiddenFailure then forbidden_error(code: error.code)
      # A provider refusing the organization's own credentials. The API key of the request is fine, so
      # not a 401: on v2, a 401 always means the Lago API key was refused. Ahead of its parent.
      when BaseService::ProviderUnauthorizedFailure
        render_provider_error(422, code: "provider_unauthorized", provider_name: error.provider.payment_type, provider_code: error.provider.code)
      when BaseService::UnauthorizedFailure then unauthorized_error
      # A provider is named by its token, never by its message: a sentence of the provider's, which
      # can echo the request. Its error code (resource_missing, card_declined) is a token of the
      # provider's, which tells an input the client can fix from a failure to retry.
      when BaseService::ProviderFailure
        render_provider_error(
          422,
          code: "provider_error",
          provider_name: error.provider.payment_type,
          provider_code: error.provider.code,
          provider_error_code: provider_error_code(error.original_error.try(:code))
        )
      when BaseService::ThirdPartyFailure
        render_provider_error(
          422,
          code: "provider_error",
          provider_name: error.third_party.to_s.downcase,
          provider_error_code: provider_error_code(error.error_code)
        )
      # throttle! names the provider with a Symbol.
      when BaseService::TooManyProviderRequestsFailure
        render_provider_error(429, code: "too_many_provider_requests", provider_name: error.provider_name&.to_s)
      # The shape of the services that already refuse with concurrency_conflict, so that a client
      # handles one. The same request can succeed once the lock is free. v1 and GraphQL keep
      # lock_acquisition_failed.
      when BaseService::LockAcquisitionFailure then validation_errors(errors: {base: ["concurrency_conflict"]})
      else raise(error)
      end
    end

    private

    # A record that no lookup names: ApplicationController rescues ActiveRecord::RecordNotFound with it.
    def not_found = render_v2_error(404, code: "resource_not_found")

    # A 400 keyed by the offending parameter, `{param => {reason:, **meta}}`. Without a reason, the
    # code of the error is the code of its entry. Its meta may echo the parameter received.
    def invalid_request_error(code:, error_details:)
      details = error_details.map do |param, detail|
        error_detail(code: detail.fetch(:reason, code), field: param, meta: detail.except(:reason), echo: true)
      end

      render_v2_error(400, code:, details:)
    end

    # A refused filter is a value like any other, with the values allowed when it names a closed list.
    def filter_errors(filters)
      details = filters.map { |filter, meta| error_detail(code: "value_is_invalid", field: filter, meta:) }

      render_v2_error(422, code: "validation_errors", details:)
    end

    # One entry per code, in order and duplicates kept, so that grouping the entries by field gives
    # the messages of the failure back.
    def render_validation_entries(entries)
      details = entries.map { error_detail(code: it.code, field: it.field, meta: it.meta) }

      render_v2_error(422, code: "validation_errors", details:)
    end

    # Some providers give an HTTP status instead of a token (Adyen, Cashfree, Flutterwave), which tells
    # the client nothing the status of the response does not.
    def provider_error_code(code)
      code = code.to_s
      code if code.match?(/\A[a-z][a-z0-9_]*\z/)
    end

    def render_provider_error(status, code:, **meta)
      render_v2_error(status, code:, details: [error_detail(code:, field: :base, meta: meta.compact)])
    end

    # Every v2 entry, 400, 422 and 429 alike, goes through the registry of meta keys and the token check.
    def error_detail(code:, field:, meta: {}, echo: false)
      {code: token_or_invalid(code, field), field: field.to_s, meta: ValidationMeta.check(meta, echo:)}
    end

    # v1 and GraphQL keep the code a service or Rails gives, a sentence included ("is not a number").
    # v2 renders it as value_is_invalid, reported so that its producer gets fixed: by its class only, as
    # a sentence can quote the request (an email address the client sent).
    def token_or_invalid(code, field)
      if (code.is_a?(String) || code.is_a?(Symbol)) && code.match?(TOKEN)
        code
      else
        ValidationMeta.report("code of #{field} is not a token: #{code.class}")
        "value_is_invalid"
      end
    end

    def render_v2_error(status, code:, details: [])
      render(json: {code:, details:}, status:)
    end
  end
end
