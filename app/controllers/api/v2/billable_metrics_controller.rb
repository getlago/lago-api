# frozen_string_literal: true

module Api
  module V2
    class BillableMetricsController < BaseController
      cursor_paginated_index(BillableMetric)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::BillableMetricSerializer

      def index
        result = ::BillableMetricsQuery.call(organization: current_organization, pagination: cursor, filters: date_range_filters)

        if result.success?
          render_billable_metrics(result.billable_metrics)
        else
          render_error_response(result)
        end
      end

      def show
        metric = current_organization.billable_metrics.find_by(code: params[:code])

        if metric
          render_billable_metric(metric)
        else
          not_found_error(resource: "billable_metric")
        end
      end

      def create
        input = input_params
        validation = ::BillableMetrics::ValidateApiInputService.call(params: input)
        return render_error_response(validation) unless validation.success?

        result = ::BillableMetrics::CreateService.call(input.merge(organization_id: current_organization.id))

        if result.success?
          render_billable_metric(result.billable_metric)
        else
          render_error_response(result)
        end
      end

      def update
        metric = current_organization.billable_metrics.find_by(code: params[:code])
        return not_found_error(resource: "billable_metric") unless metric

        input = input_params
        validation = ::BillableMetrics::ValidateApiInputService.call(params: input)
        return render_error_response(validation) unless validation.success?

        result = ::BillableMetrics::UpdateService.call(billable_metric: metric, params: input, reject_locked_changes: true)

        if result.success?
          render_billable_metric(result.billable_metric)
        else
          render_error_response(result)
        end
      end

      def destroy
        metric = current_organization.billable_metrics.find_by(code: params[:code])
        result = ::BillableMetrics::DestroyService.call(metric:)

        if result.success?
          render_billable_metric(result.billable_metric)
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.expect(billable_metric: [
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
          filters: [[:key, values: []]]
        ]).to_h.deep_symbolize_keys
      end

      def resource_name
        "billable_metric"
      end
    end
  end
end
