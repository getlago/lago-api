# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Gocardless::HandleEventJob do
  subject(:handle_event_job) { described_class }

  let(:gocardless_service) { instance_double(PaymentProviders::GocardlessService) }
  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:gocardless_provider, organization:) }

  let(:event_json) do
    path = Rails.root.join("spec/fixtures/gocardless/events.json")
    JSON.parse(File.read(path))["events"].first.to_json
  end

  let(:service_result) { BaseService::Result.new }

  describe "unique job behavior" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    it "does not enqueue duplicate jobs" do
      expect do
        described_class.perform_later(payment_provider:, event_json:)
        described_class.perform_later(payment_provider:, event_json:)
      end.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
    end
  end

  it "delegate to the event service" do
    allow(PaymentProviders::Gocardless::HandleEventService).to receive(:call)
      .with(payment_provider:, event_json:)
      .and_return(service_result)

    handle_event_job.perform_now(organization:, payment_provider:, event_json:)

    expect(PaymentProviders::Gocardless::HandleEventService).to have_received(:call)
  end

  context "with legacy multiple events" do
    let(:events_json) do
      path = Rails.root.join("spec/fixtures/gocardless/events.json")
      File.read(path)
    end

    it "enqueues a job for each event" do
      handle_event_job.perform_now(events_json:)

      expect(described_class).to have_been_enqueued.exactly(JSON.parse(events_json)["events"].count).times
    end
  end
end
