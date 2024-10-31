# frozen_string_literal: true

module Api
  module V1
    class BillableMetricsController < Api::BaseController
      def create
        result = ::BillableMetrics::CreateService.call(
          input_params.merge(organization_id: current_organization.id).to_h.deep_symbolize_keys
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: "billable_metric"
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
          params: input_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render(
            json: ::V1::BillableMetricSerializer.new(
              result.billable_metric,
              root_name: "billable_metric"
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
              root_name: "billable_metric"
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

        return not_found_error(resource: "billable_metric") unless metric

        render(
          json: ::V1::BillableMetricSerializer.new(
            metric,
            root_name: "billable_metric"
          )
        )
      end

      def index
        metrics = current_organization.billable_metrics
          .includes(:filters)
          .order(created_at: :desc)
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            metrics,
            ::V1::BillableMetricSerializer,
            collection_name: "billable_metrics",
            meta: pagination_metadata(metrics)
          )
        )
      end

      def evaluate_expression
        result = ::BillableMetrics::EvaluateExpressionService.call(
          expression: params[:expression],
          event: expression_event_params[:event]
        )

        if result.success?
          render(
            json: ::V1::BillableMetricExpressionResultSerializer.new(
              result,
              root_name: "expression_result"
            )
          )
        else
          render_error_response(result)
        end
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
          :expression,
          :rounding_function,
          :rounding_precision,
          filters: [:key, {values: []}]
        )
      end

      def expression_event_params
        params.permit(event: [
          :code,
          :timestamp,
          properties: {}
        ])
      end
    end
  end
end
