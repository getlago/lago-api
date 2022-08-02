# frozen_string_literal: true

class BaseService
  class FailedResult < StandardError
    def initialize(result)
      super(format_message(result))
    end

    private

    def format_message(result)
      return result.error unless result.error_details

      "#{result.error}: #{[result.error_details].flatten.join(', ')}"
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
        details: record.errors.messages
      )
    end

    def throw_error
      return if success?

      raise FailedResult, self
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
