# frozen_string_literal: true

class BaseService
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
    end

    private

    attr_accessor :failure
  end

  def initialize
    @result = Result.new
  end

  private

  attr_reader :result
end
