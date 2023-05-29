# frozen_string_literal: true

module Customers
  module AppliedTaxes
    class DestroyService < BaseService
      def initialize(applied_tax:)
        @applied_tax = applied_tax
        super
      end

      def call
        return result.not_found_failure!(resource: 'applied_tax') unless applied_tax

        applied_tax.destroy!

        result.applied_tax = applied_tax
        result
      end

      private

      attr_reader :applied_tax
    end
  end
end
