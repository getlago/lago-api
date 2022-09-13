# frozen_string_literal: true

class BaseService
  class FailedResult < StandardError
    def initialize(result)
      super(format_message(result))
    end

    private

    def format_message(result)
      return result if result.is_a?(String)
      return result.error unless result.error_details

      "#{result.error}: #{[result.error_details].flatten.join(', ')}"
    end
  end

  class NotFoundFailure < FailedResult
    attr_reader :resource

    def initialize(resource:)
      @resource = resource

      super(error_code)
    end

    def error_code
      "#{resource}_not_found"
    end
  end

  class MethodNotAllowedFailure < FailedResult
    attr_reader :code

    def initialize(code:)
      @code = code

      super(code)
    end
  end

  class Result < OpenStruct
    attr_reader :error, :error_code, :error_details

    def initialize
      super

      @failure = false
      @error = nil
    end

    def success?
      !failure
    end

    def fail!(code:, message: nil, details: nil)
      @failure = true
      @error_code = code
      @error = message || code
      @error_details = details

      # Return self to return result immediately in case of failure:
      # ```
      # return result.fail!(code: 'not_found')
      # ```
      self
    end

    def fail_with_validations!(record)
      fail!(
        code: 'unprocessable_entity',
        message: 'Validation error on the record',
        details: record.errors.messages,
      )
    end

    def fail_with_error!(error)
      @failure = true
      @error = error

      self
    end

    def not_found_failure!(resource:)
      fail_with_error!(NotFoundFailure.new(resource: resource))
    end

    def not_allowed_failure!(code:)
      fail_with_error!(MethodNotAllowedFailure.new(code: code))
    end

    def throw_error
      return if success?

      raise(error) if error.is_a?(FailedResult)

      raise(FailedResult, self)
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
