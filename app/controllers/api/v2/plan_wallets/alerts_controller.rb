# frozen_string_literal: true

module Api
  module V2
    module PlanWallets
      class AlertsController < Api::V2::BaseController
        include Api::RequiresCatalogWallets

        ALERT_FIELDS = %i[alert_type code name].freeze
        THRESHOLD_FIELDS = %i[code value recurring notify_on].freeze

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

        # Strong params would drop a list or an object, an item or a field, and save what is left. The fields go
        # through as sent, without unknown ones, so that the service refuses any malformed shape. The update takes
        # the code and the type too, which its service refuses.
        def input_params
          alert_params = params.require(:alert)
          raise ActionController::ParameterMissing, :alert unless alert_params.is_a?(ActionController::Parameters)

          sent = alert_params.to_unsafe_h
          input = sent.slice(*ALERT_FIELDS)
          input[:thresholds] = sent_thresholds(sent[:thresholds]) if sent.key?(:thresholds)
          input
        end

        def sent_thresholds(thresholds)
          return thresholds unless thresholds.is_a?(Array)

          thresholds.map { it.is_a?(Hash) ? it.slice(*THRESHOLD_FIELDS) : it }
        end

        def resource_name
          "alert"
        end
      end
    end
  end
end
