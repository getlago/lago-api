# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Adyen::HandleEventJob, type: :job do
  subject(:handle_event_job) { described_class }

  let(:adyen_service) { instance_double(PaymentProviders::AdyenService) }
  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:event_json) { "{}" }

  before do
    allow(PaymentProviders::AdyenService).to receive(:new)
      .and_return(adyen_service)
    allow(adyen_service).to receive(:handle_event)
      .and_return(result)
  end

  it "calls the handle event service" do
    described_class.perform_now(organization:, event_json:)

    expect(PaymentProviders::AdyenService).to have_received(:new)
    expect(adyen_service).to have_received(:handle_event)
  end
end
