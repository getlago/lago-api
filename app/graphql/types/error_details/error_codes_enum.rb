# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ErrorDetails
    class ErrorCodesEnum < Types::BaseEnum
      ErrorDetail::ERROR_CODES.keys.each do |code|
        value code
      end
    end
  end
end
