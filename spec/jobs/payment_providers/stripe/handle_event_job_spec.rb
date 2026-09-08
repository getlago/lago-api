# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::HandleEventJob do
  let(:result) { PaymentProviders::Stripe::HandleEventService::Result.new }
  let(:organization) { create(:organization) }

  let(:stripe_event) do
    {}
  end

  before do
    allow(PaymentProviders::Stripe::HandleEventService)
      .to receive(:call)
      .and_return(result)
  end

  it "calls the handle event service" do
    described_class.perform_now(
      organization:,
      event: stripe_event
    )

    expect(PaymentProviders::Stripe::HandleEventService).to have_received(:call)
  end

  context "when the service raises BaseService::LockAcquisitionFailure" do
    before do
      allow(PaymentProviders::Stripe::HandleEventService).to receive(:call)
        .and_raise(BaseService::LockAcquisitionFailure.new(nil, code: "lock_acquisition_failed", error_message: "Failed to acquire lock"))
    end

    it "retries the job instead of dying" do
      expect do
        described_class.perform_now(organization:, event: stripe_event)
      end.to have_enqueued_job(described_class)
    end
  end

  context "when the service raises ActiveRecord::Deadlocked" do
    before do
      allow(PaymentProviders::Stripe::HandleEventService).to receive(:call).and_raise(ActiveRecord::Deadlocked)
    end

    it "retries the job instead of dying" do
      expect do
        described_class.perform_now(organization:, event: stripe_event)
      end.to have_enqueued_job(described_class)
    end
  end
end
