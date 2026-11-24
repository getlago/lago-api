# frozen_string_literal: true

module Api
  module V2
    module PlanWallets
      class AlertsController < Api::V2::BaseController
        include Api::RequiresCatalogWallets
        include Api::CatalogWalletAlertParams

        serializable_with ::V2::CatalogWalletAlertSerializer

        # A wallet holds at most one alert per metric, so the list is returned whole.
        before_action :reject_pagination!, only: :index
        before_action :ensure_plan_wallet
        before_action :find_alert, only: %i[show update destroy]

        def index
          render_alerts(plan_wallet.alerts.includes(:thresholds).order(::CursorPagination::DEFAULT_SORT))
        end

        def show
          render_alert(alert)
        end

        def create
          result = ::UsageMonitoring::CatalogWalletAlerts::CreateService.call(plan_wallet:, params: input_params)

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        def update
          result = ::UsageMonitoring::CatalogWalletAlerts::UpdateService.call(alert:, params: input_params)

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        def destroy
          result = ::UsageMonitoring::CatalogWalletAlerts::DestroyService.call(alert:)

          if result.success?
            render_alert(result.alert)
          else
            render_error_response(result)
          end
        end

        private

        attr_reader :alert

        def ensure_plan_wallet
          not_found_error(resource: "plan_wallet") unless plan_wallet
        end

        def find_alert
          @alert = plan_wallet.alerts.find_by(code: params[:code])

          not_found_error(resource: "alert") unless alert
        end

        def plan_wallet
          return @plan_wallet if defined?(@plan_wallet)

          catalog_plan = current_organization.catalog_plans.find_by(code: params[:plan_code])
          @plan_wallet = catalog_plan&.wallets&.find_by(code: params[:wallet_code])
        end

        def resource_name
          "alert"
        end
      end
    end
  end
end
