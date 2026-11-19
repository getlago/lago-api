# frozen_string_literal: true

module Api
  module V2
    module PlanWallets
      class AlertsController < Api::V2::BaseController
        include Api::RequiresCatalogWallets

        serializable_with ::V2::CatalogWalletAlertSerializer

        # A wallet holds at most one alert per metric, so the list is returned whole.
        before_action :reject_pagination!, only: :index
        before_action :ensure_plan_wallet

        def index
          render_alerts(plan_wallet.alerts.includes(:thresholds).order(::CursorPagination::DEFAULT_SORT))
        end

        def show
          alert = plan_wallet.alerts.find_by(code: params[:code])
          return not_found_error(resource: "alert") unless alert

          render_alert(alert)
        end

        private

        def ensure_plan_wallet
          not_found_error(resource: "plan_wallet") unless plan_wallet
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
