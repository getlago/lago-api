# frozen_string_literal: true

module Types
  module ErrorDetails
    class ErrorCodesEnum < Types::BaseEnum
      graphql_name 'ErrorCodesEnum'

      ErrorDetail::ERROR_CODES.each do |code|
        value code
      end
    end
  end
end
