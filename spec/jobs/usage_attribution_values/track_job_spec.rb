# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValues::TrackJob do
  let(:organization) { create(:organization) }
  let(:entries) { [{"external_subscription_id" => "sub_1", "labels" => {"user" => "alice"}, "seen_at" => Time.current.iso8601(6)}] }

  it "calls the track service" do
    allow(UsageAttributionValues::TrackService).to receive(:call!)

    described_class.perform_now(organization, entries)

    expect(UsageAttributionValues::TrackService).to have_received(:call!).with(organization:, entries:)
  end
end
