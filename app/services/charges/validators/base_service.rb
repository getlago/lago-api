# frozen_string_literal: true

module Charges
  module Validators
    class BaseService < ::BaseService
      def initialize(charge:)
        @charge = charge

        super(nil)
      end

      def validate
        # Override in subclasses
      end

      private

      attr_reader :charge

      delegate :properties, to: :charge
    end
  end
end
