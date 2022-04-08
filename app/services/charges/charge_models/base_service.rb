# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
      def initialize(charge:)
        super(nil)
        @charge = charge
      end

      def apply(value:)
        raise NotImplementedError
      end

      protected

      attr_accessor :charge
    end
  end
end
