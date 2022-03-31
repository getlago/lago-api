# frozen_string_literal: true

class BaseService
  class FailedResult < StandardError; end

  class Result < OpenStruct
    attr_reader :error, :error_code

    def initialize
      super

      @failure = false
      @error = nil
    end

    def success?
      !failure
    end

    def fail!(code, message = nil)
      @failure = true
      @error_code = code
      @error = message || code

      # Return self to return result immediately in case of failure:
      # ```
      # return result.fail!('not_found')
      # ```
      self
    end

    def fail_with_validations!(record)
      fail!('unprocessable_entity', record.errors.full_messages)
    end

    def throw_error
      return if success?

      FailedResult.new(error)
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
