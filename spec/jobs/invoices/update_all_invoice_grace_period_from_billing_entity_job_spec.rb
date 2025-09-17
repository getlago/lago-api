# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateAllInvoiceGracePeriodFromBillingEntityJob do
  subject { described_class.perform_now(billing_entity, old_grace_period) }

  let(:billing_entity) { create(:billing_entity) }
  let(:old_grace_period) { 1 }

  before do
    allow(Invoices::UpdateAllInvoiceGracePeriodFromBillingEntityService)
      .to receive(:call)
      .with(billing_entity:, old_grace_period:)
      .and_call_original
  end

  it "calls the service" do
    subject

    expect(Invoices::UpdateAllInvoiceGracePeriodFromBillingEntityService)
      .to have_received(:call)
  end
end
