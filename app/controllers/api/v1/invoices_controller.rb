# frozen_string_literal: true

module Api
  module V1
    class InvoicesController < Api::BaseController
      def update
        service = Invoices::UpdateService.new
        result = service.update_from_api(
          invoice_id: params[:id],
          params: update_params,
        )

        if result.success?
          render(
            json: ::V1::InvoiceSerializer.new(
              result.invoice,
              root_name: 'invoice',
            ),
          )
        else
          validation_errors(result)
        end
      end

      private

      def update_params
        params.require(:invoice).permit(:status)
      end
    end
  end
end
