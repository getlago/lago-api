# frozen_string_literal: true

module Api
  module V2
    module ContractWallets
      class AlertsController < Api::V2::BaseController
        include Api::RequiresCatalogWallets
        include Api::V2::ContractLookup
        include Api::CatalogWalletAlertParams

        serializable_with ::V2::CatalogWalletAlertSerializer

        # A wallet holds at most one alert per metric, so the list is returned whole.
        before_action :reject_pagination!, only: :index
        before_action :ensure_contract_wallet
        before_action :find_alert, only: %i[show update destroy]

        def index
          render_alerts(contract_wallet.alerts.includes(:thresholds).order(::CursorPagination::DEFAULT_SORT))
        end

        def show
          render_alert(alert)
        end

        def create
          result = ::UsageMonitoring::CatalogWalletAlerts::CreateService.call(catalog_wallet: contract_wallet, params: input_params)

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

        def ensure_contract_wallet
          not_found_error(resource: "contract_wallet") unless contract_wallet
        end

        def find_alert
          @alert = contract_wallet.alerts.find_by(code: params[:code])

          not_found_error(resource: "alert") unless alert
        end

        def contract_wallet
          return @contract_wallet if defined?(@contract_wallet)

          @contract_wallet = find_contract(params[:contract_external_id])&.wallets&.find_by(code: params[:wallet_code])
        end

        def resource_name
          "alert"
        end
      end
    end
  end
end
