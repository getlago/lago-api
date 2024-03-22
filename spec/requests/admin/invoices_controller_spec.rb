# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::InvoicesController, type: [:request, :admin] do
  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }

  let(:generate_service) do
    instance_double(Invoices::GeneratePdfService)
  end

  before do
    allow(Invoices::GeneratePdfService).to receive(:new)
      .with(invoice:, context: 'admin')
      .and_return(generate_service)
    allow(generate_service).to receive(:call)
      .and_return(result)
  end

  describe 'POST /admin/invoices/:id/regenerate' do
    it 'regenerates the invoice PDF' do
      admin_post("/admin/invoices/#{invoice.id}/regenerate")

      expect(Invoices::GeneratePdfService).to have_received(:new)
      expect(response).to have_http_status(:success)
    end
  end
end
