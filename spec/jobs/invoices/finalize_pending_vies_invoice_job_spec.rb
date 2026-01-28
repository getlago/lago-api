# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizePendingViesInvoiceJob do
  let(:invoice) { create(:invoice, :pending, tax_status: "pending") }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::FinalizePendingViesInvoiceService).to receive(:call!)
      .with(invoice:)
      .and_return(result)
  end

  it "delegates to the FinalizePendingViesInvoiceService" do
    described_class.perform_now(invoice)

    expect(Invoices::FinalizePendingViesInvoiceService).to have_received(:call!).with(invoice:)
  end
end
