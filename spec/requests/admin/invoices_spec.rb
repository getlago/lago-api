# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::InvoicesController, type: [:request, :admin] do
  let(:invoice) { create(:invoice) }

  describe 'POST /admin/invoices/:id/regenerate' do
    it 'regenerates the invoice PDF' do
      admin_post("/admin/invoices/#{invoice.id}/regenerate")

      expect(response).to have_http_status(:success)
    end
  end
end
