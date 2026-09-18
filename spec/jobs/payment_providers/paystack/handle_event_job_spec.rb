# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::HandleEventJob do
  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:paystack_provider, organization:) }
  let(:event_json) { {"event" => "charge.success", "data" => {"reference" => "ref_123"}} }
  let(:result) { BaseService::Result.new }

  before do
    allow(PaymentProviders::Paystack::HandleEventService).to receive(:call!).and_return(result)
  end

  it "calls the handle event service with resolved records" do
    described_class.perform_now(organization.id, payment_provider.id, event_json)

    expect(PaymentProviders::Paystack::HandleEventService).to have_received(:call!).with(
      organization:,
      payment_provider:,
      event_json:
    )
  end

  it "lets service exceptions propagate for job retry" do
    allow(PaymentProviders::Paystack::HandleEventService).to receive(:call!).and_raise(StandardError, "retry me")

    expect { described_class.perform_now(organization.id, payment_provider.id, event_json) }
      .to raise_error(StandardError, "retry me")
  end
end
