# frozen_string_literal: true

module DevTools
  class InvoicesController < ApplicationController
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
