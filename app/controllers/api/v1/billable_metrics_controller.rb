# frozen_string_literal: true

module Api
  module V1
    class BillableMetricsController < Api::BaseController
      def create
        service = ::BillableMetrics::CreateService.new
        result = service.create(
          BillableMetricInput.new(
            current_organization,
            input_params.merge(organization_id: current_organization.id).to_h.deep_symbolize_keys
          ).create_input
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric'
            )
          )
        else
          render_error_response(result)
        end
      end

      def update
        billable_metric = BillableMetric.find_by(
          code: params[:code],
          organization_id: current_organization.id
        )

        result = ::BillableMetrics::UpdateService.call(
          billable_metric:,
          params: BillableMetricInput.new(
            current_organization,
            input_params.to_h.deep_symbolize_keys
          ).update_input
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric'
            )
          )
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::BillableMetrics::DestroyService.call(
          metric: current_organization.billable_metrics.find_by(code: params[:code])
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: 'billable_metric'
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        metric = current_organization.billable_metrics.find_by(
          code: params[:code]
        )

        return not_found_error(resource: 'billable_metric') unless metric

        render(
          json: ::V1::BillableMetricSerializer.new(
            metric,
            root_name: 'billable_metric'
          )
        )
      end

      def index
        metrics = current_organization.billable_metrics
          .includes(:filters, :groups)
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            metrics,
            ::V1::BillableMetricSerializer,
            collection_name: 'billable_metrics',
            meta: pagination_metadata(metrics)
          )
        )
      end

      private

      def input_params
        params.require(:billable_metric).permit(
          :name,
          :code,
          :description,
          :aggregation_type,
          :weighted_interval,
          :recurring,
          :field_name,
          filters: [:key, {values: []}],
          group: {}
        )
      end
    end
  end
end
