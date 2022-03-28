# frozen_string_literal: true

module Api
  module V1
    class CustomersController < Api::BaseController
      def create
        service = CustomersService.new
        result = service.create(
          organization: current_organization,
          params: create_params
        )

        if result.success?
          render(
            json: ::V1::CustomerSerializer.new(
              result.customer,
              root_name: 'customer'
            )
          )
        else
          render json: { message: result.error }, status: :unprocessable_entity
        end
      end

      private

      def create_params
        params.require(:customer).permit(:external_id, :name)
      end
    end
  end
end
