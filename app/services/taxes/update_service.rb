# frozen_string_literal: true

module Taxes
  class UpdateService < BaseService
    def initialize(tax:, params:)
      @tax = tax
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'tax') unless tax

      tax.name = params[:name] if params.key?(:name)
      tax.code = params[:code] if params.key?(:code)
      tax.rate = params[:rate] if params.key?(:rate)
      tax.description = params[:description] if params.key?(:description)
      tax.applied_to_organization = params[:applied_to_organization] if params.key?(:applied_to_organization)

      tax.save!

      Invoices::RefreshBatchJob.perform_later(draft_invoice_ids)

      result.tax = tax
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :tax, :params

    def draft_invoice_ids
      @draft_invoice_ids ||= tax.organization.invoices
        .where(customer_id: tax.applicable_customers.select(:id))
        .draft
        .pluck(:id)
    end
  end
end
