# frozen_string_literal: true

module Api
  module V1
    class CustomersController < Api::BaseController
      def create
        service = CustomersService.new
        result = service.create_from_api(
          organization: current_organization,
          params: create_params,
        )

        if result.success?
          render(
            json: ::V1::CustomerSerializer.new(
              result.customer,
              root_name: 'customer'
            )
          )
        else
          validation_errors(result.error)
        end
      end

      private

      def create_params
        params.require(:customer).permit(:customer_id, :name)
      end
    end
  end
end
