# frozen_string_literal: true

module Api
  module V1
    class SupersetController < Api::BaseController
      def guest_token
        result = SupersetAuthService.call(
          organization: current_organization,
          dashboard_id: params[:dashboard_id],
          user: user_params
        )

        if result.success?
          render json: {
            guest_token: result.guest_token,
            access_token: result.access_token
          }
        else
          render_error_response(result)
        end
      end

      private

      def user_params
        return nil unless params[:user].present?

        params.require(:user).permit(:first_name, :last_name, :username).to_h
      end

      def resource_name
        "analytic"
      end
    end
  end
end
