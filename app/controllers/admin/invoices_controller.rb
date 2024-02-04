# frozen_string_literal: true

module Admin
  class InvoicesController < BaseController
    skip_before_action :authenticate, only: :show

    def regenerate
      result = ::Invoices::GeneratePdfService.call(invoice:, context: 'admin')

      return render_error_response(result) unless result.success?

      head(:ok)
    end

    def show
      service = ::Invoices::GeneratePdfService.new(invoice:)

      render(html: service.render_html)
    end

    private

    def invoice
      @invoice ||= Invoice.find(params[:id])
    end
  end
end
