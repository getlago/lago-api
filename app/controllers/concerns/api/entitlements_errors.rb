# frozen_string_literal: true

module Api
  # The errors of a native v2 write of an entitlements map, `{feature_code => {privilege_code => scalar}}`.
  module EntitlementsErrors
    extend ActiveSupport::Concern

    private

    # The service renders its validation failures on the path of the entry for native v2. An unknown
    # feature or privilege of the body, a 404 on v1, is a 422 on entitlements.<feature>[.<privilege>].
    def render_entitlements_error(result)
      field = result.failed_field
      error = result.error
      return render_error_response(result) unless field && error.is_a?(BaseService::NotFoundFailure)

      validation_errors(errors: {field => ["resource_not_found"]}, meta: {field => {resource: error.resource}})
    end
  end
end
