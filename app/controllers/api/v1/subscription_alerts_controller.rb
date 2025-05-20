# frozen_string_literal: true

module Api
  module V1
    class SubscriptionAlertsController < Api::BaseController
      before_action :ensure_subscription
      attr_reader :subscription

      def index
        result = UsageMonitoring::AlertsQuery.call(
          organization: current_organization,
          filters: {
            subscription_external_id: subscription.external_id
          },
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.alerts.includes(:thresholds, :billable_metric),
              ::V1::UsageMonitoring::AlertSerializer,
              collection_name: "alerts",
              meta: pagination_metadata(result.alerts),
              includes: %i[thresholds]
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        alert = get_alert

        if alert
          render_alert(alert)
        else
          not_found_error(resource: "alert")
        end
      end

      def create
        result = UsageMonitoring::CreateAlertService.call(
          organization: current_organization,
          subscription:,
          params: create_params.to_h
        )

        if result.success?
          render_alert(result.alert)
        else
          render_error_response(result)
        end
      end

      def update
        result = UsageMonitoring::UpdateAlertService.call(
          alert: get_alert,
          params: update_params.to_h
        )

        if result.success?
          render_alert(result.alert)
        else
          render_error_response(result)
        end
      end

      def destroy
        result = UsageMonitoring::DestroyAlertService.call(alert: get_alert)

        if result.success?
          render_alert(result.alert)
        else
          render_error_response(result)
        end
      end

      private

      def get_alert
        current_organization.alerts.find_by(
          subscription_external_id: subscription.external_id,
          code: params[:code]
        )
      end

      def render_alert(alert)
        render(
          json: ::V1::UsageMonitoring::AlertSerializer.new(
            alert,
            root_name: "alert",
            includes: %i[thresholds]
          )
        )
      end

      def create_params
        params.require(:alert).permit(:alert_type, :code, :name, :billable_metric_code, thresholds: %i[code value recurring])
      end

      def update_params
        params.require(:alert).permit(:code, :name, :billable_metric_code, thresholds: %i[code value recurring])
      end

      def resource_name
        "subscription"
      end

      def ensure_subscription
        @subscription = current_organization.subscriptions.find_by!(external_id: params[:subscription_external_id])
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "subscription")
      end
    end
  end
end
