# frozen_string_literal: true

module ChargeFilters
  class UpdateService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(charge_filter:, params:)
      @charge_filter = charge_filter
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "charge_filter") unless charge_filter

      ActiveRecord::Base.transaction do
        charge_filter.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
        charge_filter.properties = filtered_properties if params.key?(:properties)
        charge_filter.save!

        result.charge_filter = charge_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge_filter, :params

    delegate :charge, to: :charge_filter

    def filtered_properties
      ChargeModels::FilterPropertiesService.call(
        chargeable: charge,
        properties: params[:properties]
      ).properties
    end
  end
end
