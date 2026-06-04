# frozen_string_literal: true

module OpenapiFirstHelper
  def assert_api_conform(status: nil, api: openapi_first_default_api, skip_request: false)
    api = OpenapiFirst::Test[api]
    # :nocov:
    request = respond_to?(:last_request) ? last_request : @request
    response = respond_to?(:last_response) ? last_response : @response
    # :nocov:

    if status && status != response.status
      raise OpenapiFirst::Error,
        "Expected status #{status}, but got #{response.status} " \
        "from #{request.request_method.upcase} #{request.path}."
    end

    unless skip_request
      validated = api.validate_request(request, raise_error: false)
      # :nocov:
      raise validated.error.exception if validated.invalid?
    end

    validated = api.validate_response(request, response, raise_error: false)
    raise validated.error.exception if validated.invalid?
    # :nocov:
  end
end
