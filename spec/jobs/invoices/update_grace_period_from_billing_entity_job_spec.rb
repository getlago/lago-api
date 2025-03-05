# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateGracePeriodFromBillingEntityJob, type: :job do
  subject { described_class.perform_now(invoice, old_grace_period) }

  let(:invoice) { create(:invoice) }
  let(:old_grace_period) { 1 }

  it "calls the service" do
    allow(Invoices::UpdateGracePeriodFromBillingEntityService).to receive(:call).with(invoice:, old_grace_period:).and_call_original

    subject

    expect(Invoices::UpdateGracePeriodFromBillingEntityService).to have_received(:call)
  end
end
