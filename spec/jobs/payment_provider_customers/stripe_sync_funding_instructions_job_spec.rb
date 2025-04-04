# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::StripeSyncFundingInstructionsJob, type: :job do
  subject(:job) { described_class }

  let(:stripe_customer) { create(:stripe_customer) }
  let(:service_instance) { instance_double(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService) }
  let(:result) { instance_double(BaseService::Result, raise_if_error!: true) }

  before do
    allow(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService)
      .to receive(:new)
      .with(stripe_customer)
      .and_return(service_instance)

    allow(service_instance).to receive(:call).and_return(result)
  end

  it "calls the Stripe SyncFundingInstructionsService and raises if error" do
    job.perform_now(stripe_customer)

    expect(PaymentProviderCustomers::Stripe::SyncFundingInstructionsService).to have_received(:new).with(stripe_customer)
    expect(service_instance).to have_received(:call)
    expect(result).to have_received(:raise_if_error!)
  end

  context "when an UnauthorizedFailure is raised" do
    before do
      allow(result).to receive(:raise_if_error!).and_raise(BaseService::UnauthorizedFailure.new("unauthorized"))
      allow(Rails.logger).to receive(:warn)
    end

    it "rescues the error and logs a warning" do
      expect {
        job.perform_now(stripe_customer)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with("unauthorized")
    end
  end
end
