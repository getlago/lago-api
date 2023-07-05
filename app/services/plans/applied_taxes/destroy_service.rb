# frozen_string_literal: true

module Plans
  module AppliedTaxes
    class DestroyService < BaseService
      def initialize(applied_tax:)
        @applied_tax = applied_tax
        super
      end

      def call
        return result.not_found_failure!(resource: 'applied_tax') unless applied_tax

        applied_tax.destroy!

        Invoices::RefreshBatchJob.perform_later(applied_tax.plan.invoices.draft.pluck(:id))

        result.applied_tax = applied_tax
        result
      end

      private

      attr_reader :applied_tax
    end
  end
end
