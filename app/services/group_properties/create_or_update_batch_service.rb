# frozen_string_literal: true

module GroupProperties
  class CreateOrUpdateBatchService < BaseService
    def initialize(charge:, properties_params:)
      @charge = charge
      @properties_params = properties_params

      super
    end

    def call
      if properties_params.empty?
        charge.group_properties.discard_all
        return result
      end

      charge.group_properties.where.not(group_id: properties_params.map { |gp| gp[:group_id] }).discard_all
      properties_params.each do |params|
        property = charge.group_properties.find_by(group_id: params[:group_id])

        if property
          property.update!(values: params[:values], invoice_display_name: params[:invoice_display_name])
        else
          charge.group_properties.create!(
            group_id: params[:group_id],
            values: params[:values],
            invoice_display_name: params[:invoice_display_name]
          )
        end
      end

      charge.plan.invoices.draft.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations

      result
    end

    private

    attr_reader :charge, :properties_params
  end
end
