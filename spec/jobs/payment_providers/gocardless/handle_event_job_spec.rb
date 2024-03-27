# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Gocardless::HandleEventJob, type: :job do
  subject(:handle_event_job) { described_class }

  let(:gocardless_service) { instance_double(PaymentProviders::GocardlessService) }
  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }

  let(:gocardless_events) do
    []
  end

  before do
    allow(PaymentProviders::GocardlessService).to receive(:new)
      .and_return(gocardless_service)
    allow(gocardless_service).to receive(:handle_event)
      .and_return(result)
  end

  it "calls the handle event service" do
    handle_event_job.perform_now(events_json: gocardless_events)

    expect(PaymentProviders::GocardlessService).to have_received(:new)
    expect(gocardless_service).to have_received(:handle_event)
  end
end
