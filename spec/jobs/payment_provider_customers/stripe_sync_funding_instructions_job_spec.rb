# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::StripeSyncFundingInstructionsJob do
  subject(:stripe_sync_funding_instructions_job) { described_class }

  let(:stripe_customer) { create(:stripe_customer) }

  it "calls the funding instructions sync service" do
    allow(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService).to receive(:call)
      .and_return(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService::Result.new)

    stripe_sync_funding_instructions_job.perform_now(stripe_customer)

    expect(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService).to have_received(:call).with(stripe_customer)
  end
end
