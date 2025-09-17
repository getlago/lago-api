# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateGracePeriodFromBillingEntityJob do
  subject { described_class.perform_now(invoice, old_grace_period) }

  let(:invoice) { create(:invoice) }
  let(:old_grace_period) { 1 }

  before do
    allow(Invoices::UpdateGracePeriodFromBillingEntityService)
      .to receive(:call)
      .with(invoice:, old_grace_period:)
      .and_call_original
  end

  it "calls the service" do
    subject

    expect(Invoices::UpdateGracePeriodFromBillingEntityService).to have_received(:call)
  end
end
