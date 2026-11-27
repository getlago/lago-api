# frozen_string_literal: true

module Api
  module V2
    module Contracts
      class AlertsController < Api::V2::BaseController
        include Api::AlertThresholdParams

        cursor_paginated_index(UsageMonitoring::ContractAlert)
        date_range_filtered_index(:created_at)
        serializable_with ::V2::ContractAlertSerializer, root: :alert

        before_action :ensure_contract, except: :create
        before_action :find_alert, only: %i[show update destroy]

        def index
          result = ::UsageMonitoring::ContractAlertsQuery.call(
            organization: current_organization,
            pagination: cursor,
            filters: {contract_external_id: params[:contract_external_id], **date_range_filters}
          )

          if result.success?
            render_alerts(result.contract_alerts)
          else
            render_error_response(result)
          end
        end

        def show
          render_alert(alert)
        end

        def create
          contract = current_organization.contracts.terminatable_by_external_id(params[:contract_external_id]) ||
            contracts.first

          result = ::UsageMonitoring::ContractAlerts::CreateService.call(
            organization: current_organization,
            contract:,
            params: input_params.with_defaults(scope: nil)
          )

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        def update
          result = ::UsageMonitoring::ContractAlerts::UpdateService.call(alert:, params: input_params)

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::UsageMonitoring::ContractAlerts::DestroyService.call(alert:)

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :alert

        def contracts
          current_organization.contracts.where(external_id: params[:contract_external_id])
        end

        def ensure_contract
          not_found_error(resource: "contract") unless contracts.exists?
        end

        def find_alert
          @alert = current_organization.contract_alerts
            .find_by(contract_external_id: params[:contract_external_id], code: params[:code])

          not_found_error(resource: "alert") unless alert
        end

        def input_params
          alert = params.require(:alert)
          input = alert.permit(:alert_type, :code, :name).to_h
          sent = alert.to_unsafe_h
          input[:scope] = sent[:scope] if alert.key?(:scope)
          # A null list leaves the thresholds as they are, as strong params did
          input[:thresholds] = sent_thresholds(sent[:thresholds]) unless sent[:thresholds].nil?
          input
        end

        def resource_name
          "alert"
        end
      end
    end
  end
end
