# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValues::TrackJob do
  let(:organization) { create(:organization) }
  let(:entries) { [{"subscription_id" => SecureRandom.uuid, "attribution_labels" => {"user" => "alice"}, "timestamp" => 1_791_457_211.0}] }

  before { allow(UsageAttributionValues::TrackService).to receive(:call!) }

  it "tracks the values of the organization" do
    described_class.perform_now(organization.id, entries)

    expect(UsageAttributionValues::TrackService).to have_received(:call!).with(organization:, entries:)
  end

  context "when the organization is unknown" do
    it "does nothing" do
      described_class.perform_now(SecureRandom.uuid, entries)

      expect(UsageAttributionValues::TrackService).not_to have_received(:call!)
    end
  end

  context "when tracking raises a transient error" do
    before { allow(UsageAttributionValues::TrackService).to receive(:call!).and_raise(ActiveRecord::ConnectionNotEstablished) }

    it "retries the job" do
      expect { described_class.perform_now(organization.id, entries) }.to have_enqueued_job(described_class).with(organization.id, entries)
    end
  end
end
