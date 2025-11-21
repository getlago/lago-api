# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateAllInvoiceIssuingDateFromBillingEntityJob do
  subject { described_class.perform_now(billing_entity, previous_issuing_date_settings) }

  let(:billing_entity) { create(:billing_entity) }
  let(:previous_issuing_date_settings) do
    {
      subscription_invoice_issuing_date_anchor: "current_period_end",
      subscription_invoice_issuing_date_adjustment: "keep_anchor",
      invoice_grace_period: 3
    }
  end

  it "calls the service" do
    expect(Invoices::UpdateAllInvoiceIssuingDateFromBillingEntityService)
      .to receive(:call)
      .with(billing_entity:, old_issuing_date_settings:)
      .and_call_original

    subject
  end
end
