# frozen_string_literal: true

module Admin
  class InvoicesController < BaseController
    def regenerate
      result = ::Invoices::GeneratePdfService.call(invoice:, context: 'admin')

      return render_error_response(result) unless result.success?

      head(:ok)
    end

    private

    def invoice
      @invoice ||= Invoice.find(params[:id])
    end
  end
end
