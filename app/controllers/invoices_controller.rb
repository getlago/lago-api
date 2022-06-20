# frozen_string_literal: true

class InvoicesController < ApplicationController
  include ActionController::MimeResponds
  include ActionController::Rendering

  def show
    respond_to do |format|
      format.html do
        render(html: Invoices::GenerateService.new(invoice: current_invoice).generate_html.html_safe)
      end

      format.pdf do
        http_client = LagoHttpClient::Client.new('http://pdf/')
      end
    end
  end

  private

  def current_invoice
    @current_invoice ||= Invoice.find(params[:id])
  end
end
