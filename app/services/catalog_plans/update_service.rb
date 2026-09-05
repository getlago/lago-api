# frozen_string_literal: true

module CatalogPlans
  class UpdateService < BaseService
    Result = BaseResult[:catalog_plan]

    def initialize(catalog_plan:, params:)
      @catalog_plan = catalog_plan
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      catalog_plan.name = params[:name] if params.key?(:name)
      catalog_plan.code = params[:code] if params.key?(:code)
      catalog_plan.description = params[:description] if params.key?(:description)
      catalog_plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      catalog_plan.currency = params[:currency] if params.key?(:currency)
      catalog_plan.save!

      result.catalog_plan = catalog_plan
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :catalog_plan, :params
  end
end
