# frozen_string_literal: true

module Plans
  module AppliedTaxes
    class CreateService < BaseService
      def initialize(plan:, tax:)
        @plan = plan
        @tax = tax
        super
      end

      def call
        return result.not_found_failure!(resource: 'plan') unless plan
        return result.not_found_failure!(resource: 'tax') unless tax

        applied_tax = plan.applied_taxes.find_or_create_by!(tax:) do |_applied_tax|
          Invoices::RefreshBatchJob.perform_later(plan.invoices.draft.pluck(:id))
        end

        result.applied_tax = applied_tax
        result
      end

      private

      attr_reader :plan, :tax
    end
  end
end
