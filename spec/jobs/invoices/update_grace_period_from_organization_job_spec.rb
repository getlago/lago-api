# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::UpdateGracePeriodFromOrganizationJob, type: :job do
  subject { described_class.perform_now(invoice, old_grace_period) }

  let(:invoice) { create(:invoice) }
  let(:old_grace_period) { 1 }

  it "calls the service" do
    allow(Invoices::UpdateGracePeriodFromOrganizationService).to receive(:call).with(invoice:, old_grace_period:).and_call_original

    subject

    expect(Invoices::UpdateGracePeriodFromOrganizationService).to have_received(:call)
  end
end
