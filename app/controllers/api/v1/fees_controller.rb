# frozen_string_literal: true

module Api
  module V1
    class FeesController < Api::BaseController
      def show
        fee = Fee.from_organization(current_organization)
          .find_by(id: params[:id])

        return not_found_error(resource: 'fee') unless fee

        render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee'))
      end

      def update
        fee = Fee.from_organization(current_organization)
          .find_by(id: params[:id])
        result = Fees::UpdateService.call(fee:, params: update_params)

        if result.success?
          render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee'))
        else
          render_error_response(result)
        end
      end

      private

      def update_params
        params.require(:fee).permit(:payment_status)
      end
    end
  end
end
