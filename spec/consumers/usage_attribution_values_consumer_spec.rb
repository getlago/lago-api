# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValuesConsumer do
  subject(:consumer) { karafka.consumer_for("usage_attribution_values") }

  # The topic is unset in tests, so karafka.rb draws no route.
  before_all do
    next if Karafka::App.routes.any? { it.name == "lago_usage_attribution_values_consumer" }

    # The routing DSL is evaluated in its own context, where described_class is not defined.
    consumer_class = described_class

    Karafka::App.routes.draw do
      consumer_group :lago_usage_attribution_values_consumer do
        topic("usage_attribution_values") { consumer consumer_class }
      end
    end
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:other_organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }

  let(:messages) do
    [
      message(organization, "sub-1", {"user" => "alice"}),
      message(other_organization, "sub-2", {"user" => "bob"}),
      message(organization, "sub-3", {"user" => "carol"})
    ]
  end

  def message(organization, subscription_id, labels)
    {"organization_id" => organization.id, "subscription_id" => subscription_id, "attribution_labels" => labels, "timestamp" => 1_791_457_211.0}
  end

  before do
    allow(UsageAttributionValues::TrackService).to receive(:call!)
    messages.each { karafka.produce(it.to_json) }
  end

  it "tracks the values of each organization once" do
    consumer.consume

    expect(UsageAttributionValues::TrackService).to have_received(:call!).twice
    expect(UsageAttributionValues::TrackService).to have_received(:call!)
      .with(organization:, entries: [messages[0], messages[2]])
    expect(UsageAttributionValues::TrackService).to have_received(:call!)
      .with(organization: other_organization, entries: [messages[1]])
  end

  context "when the organization is unknown" do
    let(:messages) { [{"organization_id" => SecureRandom.uuid, "subscription_id" => "sub-1", "attribution_labels" => {"user" => "alice"}, "timestamp" => 1.0}] }

    it "skips it" do
      consumer.consume

      expect(UsageAttributionValues::TrackService).not_to have_received(:call!)
    end
  end

  context "when a message is not a valid payload" do
    before do
      karafka.produce("not json")
      karafka.produce([1, 2].to_json)
      karafka.produce(nil)
    end

    it "skips it and tracks the others" do
      consumer.consume

      expect(UsageAttributionValues::TrackService).to have_received(:call!).twice
      expect(UsageAttributionValues::TrackService).to have_received(:call!)
        .with(organization:, entries: [messages[0], messages[2]])
    end
  end

  context "when tracking raises a transient error for an organization" do
    let(:error) { ActiveRecord::ConnectionNotEstablished.new("boom") }

    before do
      allow(UsageAttributionValues::TrackService).to receive(:call!).with(organization:, entries: anything).and_raise(error)
    end

    it "tracks the other organizations, then raises so that the batch is replayed" do
      expect { consumer.consume }.to raise_error(error)

      expect(UsageAttributionValues::TrackService).to have_received(:call!).with(organization: other_organization, entries: [messages[1]])
    end

    context "when it has been retried enough" do
      before do
        allow(consumer.coordinator.pause_tracker).to receive(:attempt).and_return(described_class::MAX_ATTEMPTS)
      end

      it "hands the failed organization to the job" do
        expect { consumer.consume }.not_to raise_error

        expect(UsageAttributionValues::TrackJob).to have_been_enqueued.once
        expect(UsageAttributionValues::TrackJob).to have_been_enqueued.with(organization.id, [messages[0], messages[2]])
      end
    end
  end

  context "when tracking raises another error for an organization" do
    let(:error) { StandardError.new("boom") }

    before do
      allow(UsageAttributionValues::TrackService).to receive(:call!).with(organization:, entries: anything).and_raise(error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports it and tracks the other organizations" do
      expect { consumer.consume }.not_to raise_error

      expect(Sentry).to have_received(:capture_exception).with(error, extra: {organization_id: organization.id})
      expect(UsageAttributionValues::TrackService).to have_received(:call!).with(organization: other_organization, entries: [messages[1]])
      expect(UsageAttributionValues::TrackJob).not_to have_been_enqueued
    end
  end
end
