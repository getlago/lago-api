# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

class ErrorSerializer
  attr_reader :error

  def initialize(error)
    @error = error
  end

  def serialize
    {
      message: error.message
    }
  end
end
