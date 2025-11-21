# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateIssuingDateFromBillingEntityJob do
  subject { described_class.perform_now(invoice, old_issuing_date_settings) }

  let(:invoice) { create(:invoice) }
  let(:old_issuing_date_settings) do
    {
      subscription_invoice_issuing_date_anchor: "current_period_end",
      subscription_invoice_issuing_date_adjustment: "keep_anchor",
      invoice_grace_period: 3
    }
  end

  before do
    allow(Invoices::UpdateIssuingDateFromBillingEntityService)
      .to receive(:call)
      .with(invoice:, old_issuing_date_settings:)
      .and_call_original
  end

  it "calls the service" do
    subject

    expect(Invoices::UpdateIssuingDateFromBillingEntityService).to have_received(:call).with(invoice:, old_issuing_date_settings:)
  end
end
