# frozen_string_literal: true

module TaxRates
  class UpdateService < BaseService
    def initialize(tax_rate:, params:)
      @tax_rate = tax_rate
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'tax_rate') unless tax_rate

      tax_rate.name = params[:name] if params.key?(:name)
      tax_rate.code = params[:code] if params.key?(:code)
      tax_rate.value = params[:value] if params.key?(:value)
      tax_rate.description = params[:description] if params.key?(:description)
      tax_rate.applied_by_default = params[:applied_by_default] if params.key?(:applied_by_default)

      tax_rate.save!

      Invoices::RefreshBatchJob.perform_later(draft_invoice_ids)

      result.tax_rate = tax_rate
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :tax_rate, :params

    def draft_invoice_ids
      @draft_invoice_ids ||= tax_rate.organization.invoices
        .where(customer_id: tax_rate.applicable_customers.select(:id))
        .draft
        .pluck(:id)
    end
  end
end
