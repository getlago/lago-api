# frozen_string_literal: true

class BaseService
  class FailedResult < StandardError
    attr_reader :result

    def initialize(result, message)
      @result = result

      super(message)
    end
  end

  class NotFoundFailure < FailedResult
    attr_reader :resource

    def initialize(result, resource:)
      @resource = resource

      super(result, error_code)
    end

    def error_code
      "#{resource}_not_found"
    end
  end

  class MethodNotAllowedFailure < FailedResult
    attr_reader :code

    def initialize(result, code:)
      @code = code

      super(result, code)
    end
  end

  class ValidationFailure < FailedResult
    attr_reader :messages

    def initialize(result, messages:)
      @messages = messages

      super(result, format_messages)
    end

    private

    def format_messages
      "Validation errors: #{[messages].flatten.join(', ')}"
    end
  end

  class ServiceFailure < FailedResult
    attr_reader :code, :error_message

    def initialize(result, code:, error_message:)
      @code = code
      @error_message = error_message

      super(result, "#{code}: #{error_message}")
    end
  end

  class Result < OpenStruct
    attr_reader :error

    def initialize
      super

      @failure = false
      @error = nil
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
      fail_with_error!(NotFoundFailure.new(self, resource: resource))
    end

    def not_allowed_failure!(code:)
      fail_with_error!(MethodNotAllowedFailure.new(self, code: code))
    end

    def record_validation_failure!(record:)
      validation_failure!(errors: record.errors.messages)
    end

    def validation_failure!(errors:)
      fail_with_error!(ValidationFailure.new(self, messages: errors))
    end

    def single_validation_failure!(error_code:, field: :base)
      validation_failure!(errors: { field.to_sym => [error_code] })
    end

    def service_failure!(code:, message:)
      fail_with_error!(ServiceFailure.new(self, code: code, error_message: message))
    end

    def throw_error
      return if success?

      raise(error)
    end

    private

    attr_accessor :failure
  end

  def initialize(current_user = nil)
    @result = Result.new
    result.user = current_user
  end

  private

  attr_reader :result
end
