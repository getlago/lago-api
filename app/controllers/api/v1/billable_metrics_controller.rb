# frozen_string_literal: true

module Api
  module V1
    class BillableMetricsController < Api::BaseController
      def create
        service = BillableMetrics::CreateService.new
        result = service.create(
          **input_params.merge(organization_id: current_organization.id)
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric',
              ),
            )
        else
          validation_errors(result)
        end
      end

      def update
        service = BillableMetrics::UpdateService.new
        result = service.update_from_api(
          code: params[:code],
          params: input_params,
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric',
              ),
            )
        elsif result.error_code == 'not_found'
          not_found_error
        else
          validation_errors(result)
        end
      end

      private

      def input_params
        params.require(:billable_metric).permit(
          :name,
          :code,
          :description,
          :aggregation_type,
          :field_name,
        )
      end
    end
  end
end
