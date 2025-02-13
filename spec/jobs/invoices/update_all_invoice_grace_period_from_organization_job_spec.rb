# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::UpdateAllInvoiceGracePeriodFromOrganizationJob, type: :job do
  subject { described_class.perform_now(organization, old_grace_period) }

  let(:organization) { create(:organization) }
  let(:old_grace_period) { 1 }

  it "calls the service" do
    allow(Invoices::UpdateAllInvoiceGracePeriodFromOrganizationService).to receive(:call).with(organization:, old_grace_period:).and_call_original

    subject

    expect(Invoices::UpdateAllInvoiceGracePeriodFromOrganizationService).to have_received(:call)
  end
end
