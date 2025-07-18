# frozen_string_literal: true

module Api
  module V1
    module DataApi
      class ChargesController < Api::BaseController
        include PremiumFeatureOnly

        attr_reader :charge, :charge_filter

        before_action :find_charge, only: :forecasted_usage_amount
        before_action :find_charge_filter, only: :forecasted_usage_amount

        def forecasted_usage_amount
          result = Charges::CalculatePriceService.call(units: params[:units], charge:, charge_filter:)

          if result.success?
            json = result.as_json.slice("charge_amount_cents", "subscription_amount_cents", "total_amount_cents")
            render json:
          else
            render_error_response(result)
          end
        end

        private

        def find_charge
          @charge = Charge.where(organization: current_organization).find_by!(id: params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "charge")
        end

        def find_charge_filter
          @charge_filter = if params[:charge_filter_id].present?
            ChargeFilter.where(organization: current_organization).find_by!(id: params[:charge_filter_id])
          end
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "charge_filter")
        end

        def resource_name
          "analytic"
        end
      end
    end
  end
end
