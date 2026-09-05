# frozen_string_literal: true

module CatalogPlans
  class CreateService < BaseService
    Result = BaseResult[:catalog_plan]

    def initialize(args)
      @args = args
      super()
    end

    def call
      catalog_plan = CatalogPlan.new(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        description: args[:description],
        invoice_display_name: args[:invoice_display_name],
        currency: args[:currency]
      )
      catalog_plan.save!

      result.catalog_plan = catalog_plan
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :args
  end
end
