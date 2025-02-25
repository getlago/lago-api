# frozen_string_literal: true

class BaseResult
  def self.[](*attributes)
    Class.new(BaseResult) { attr_accessor(*attributes) }
  end

  attr_reader :error

  def initialize
    @failure = false
    @error = nil
  end

  def failure?
    failure
  end

  def success?
    !failure
  end

  def fail_with_error!(error)
    @failure = true
    @error = error

    self
  end

  def not_found_failure!(resource:)
    fail_with_error!(BaseService::NotFoundFailure.new(self, resource:))
  end

  def not_allowed_failure!(code:)
    fail_with_error!(BaseService::MethodNotAllowedFailure.new(self, code:))
  end

  def record_validation_failure!(record:)
    validation_failure!(errors: record.errors.messages)
  end

  def validation_failure!(errors:)
    fail_with_error!(BaseService::ValidationFailure.new(self, messages: errors))
  end

  def single_validation_failure!(error_code:, field: :base)
    validation_failure!(errors: {field.to_sym => [error_code]})
  end

  def service_failure!(code:, message:)
    fail_with_error!(BaseService::ServiceFailure.new(self, code:, error_message: message))
  end

  def unknown_tax_failure!(code:, message:)
    fail_with_error!(BaseService::UnknownTaxFailure.new(self, code:, error_message: message))
  end

  def forbidden_failure!(code: "feature_unavailable")
    fail_with_error!(BaseService::ForbiddenFailure.new(self, code:))
  end

  def unauthorized_failure!(message: "unauthorized")
    fail_with_error!(BaseService::UnauthorizedFailure.new(self, message:))
  end

  def third_party_failure!(third_party:, error_code:, error_message:)
    fail_with_error!(BaseService::ThirdPartyFailure.new(self, third_party:, error_code:, error_message:))
  end

  def raise_if_error!
    return self if success?

    raise(error)
  end

  private

  attr_accessor :failure
end
