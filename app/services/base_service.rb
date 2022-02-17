# frozen_string_literal: true

class BaseService
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

    def fail!(message)
      @failure = true
      @error = message
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
