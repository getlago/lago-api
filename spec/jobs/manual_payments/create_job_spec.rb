# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManualPayments::CreateJob, type: :job do
  let(:organization) { invoice.customer.organization }
  let(:invoice) { create(:invoice) }
  let(:params) { {invoice_id: invoice.id, amount_cents: invoice.total_amount_cents, reference: 'ref1'} }

  it "calls the create service" do
    allow(ManualPayments::CreateService)
      .to receive(:call!).with(organization:, params:, skip_checks: false).and_return(BaseService::Result.new)

    described_class.perform_now(organization:, params:)

    expect(ManualPayments::CreateService).to have_received(:call!)
  end
end
