# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < Api::BaseController
      def create

      end

      private

      def create_params
        params.require(:subscription)
          .permit(:customer_id, :price_plan_code)
      end
    end
  end
end
