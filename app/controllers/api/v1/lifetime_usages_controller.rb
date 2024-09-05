# frozen_string_literal: true

module Api
  module V1
    class LifetimeUsagesController < Api::BaseController
      def show
        lifetime_usage = current_organization.subscriptions
          .find_by(external_id: params[:subscription_external_id])&.lifetime_usage

        return not_found_error(resource: 'lifetime_usage') unless lifetime_usage
        render_lifetime_usage lifetime_usage
      end

      def update
        lifetime_usage = current_organization.subscriptions
          .find_by(external_id: params[:subscription_external_id])&.lifetime_usage

        result = LifetimeUsages::UpdateService.call(
          lifetime_usage:,
          params: update_params.to_h
        )
        if result.success?
          render_lifetime_usage lifetime_usage
        else
          render_error_response(result)
        end
      end

      private

      def update_params
        params.require(:lifetime_usage).permit(
          :external_historical_usage_amount_cents
        )
      end

      def render_lifetime_usage(lifetime_usage)
        render(
          json: ::V1::LifetimeUsageSerializer.new(
            lifetime_usage,
            root_name: 'lifetime_usage',
            includes: %i[usage_thresholds]
          )
        )
      end
    end
  end
end
