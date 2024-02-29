# frozen_string_literal: true

module Charges
  module Validators
    class BaseService < BaseValidator
      def initialize(charge:, properties: nil)
        @charge = charge
        @properties = properties || charge.properties
        @result = ::BaseService::Result.new

        super(result)
      end

      def valid?
        # NOTE: override and add validation rules

        if errors?
          result.validation_failure!(errors:)
          return false
        end

        true
      end

      attr_reader :result, :properties

      private

      attr_reader :charge
    end
  end
end
