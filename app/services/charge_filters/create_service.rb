# frozen_string_literal: true

module ChargeFilters
  class CreateService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(charge:, params:)
      @charge = charge
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge
      return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory") if params[:values].blank?

      ActiveRecord::Base.transaction do
        charge_filter = charge.filters.create!(
          organization_id: charge.organization_id,
          invoice_display_name: params[:invoice_display_name],
          properties: filtered_properties
        )

        create_filter_values(charge_filter)

        result.charge_filter = charge_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge, :params

    def filtered_properties
      ChargeModels::FilterPropertiesService.call(
        chargeable: charge,
        properties: params[:properties]
      ).properties
    end

    def create_filter_values(charge_filter)
      params[:values].each do |key, values|
        billable_metric_filter = charge.billable_metric.filters.find_by(key:)

        filter_value = charge_filter.values.new(
          billable_metric_filter_id: billable_metric_filter&.id,
          organization_id: charge.organization_id
        )
        filter_value.values = values
        filter_value.save!
      end
    end
  end
end
