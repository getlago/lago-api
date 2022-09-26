# frozen_string_literal: true

module Charges
  module Validators
    class BaseService < BaseValidator
      def initialize(charge:)
        @charge = charge
        @result = ::BaseService::Result.new

        super(result)
      end

      def valid?
        # NOTE: override and add validation rules

        if errors?
          result.validation_failure!(errors: errors)
          return false
        end

        true
      end

      attr_reader :result

      private

      attr_reader :charge

      delegate :properties, to: :charge
    end
  end
end
