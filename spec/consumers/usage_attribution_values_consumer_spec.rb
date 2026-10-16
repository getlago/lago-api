# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValuesConsumer do
  subject(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_USAGE_ATTRIBUTION_VALUES_TOPIC"]) }

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

  context "without the account_tree feature flag" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "skips the organization" do
      consumer.consume

      expect(UsageAttributionValues::TrackService).not_to have_received(:call!).with(organization:, entries: anything)
    end
  end

  context "when the organization uses the Postgres events store" do
    let(:organization) { create(:organization, clickhouse_events_store: false, feature_flags: ["account_tree"]) }

    it "skips the organization" do
      consumer.consume

      expect(UsageAttributionValues::TrackService).not_to have_received(:call!).with(organization:, entries: anything)
    end
  end

  context "when tracking fails for an organization" do
    let(:error) { ActiveRecord::StatementInvalid.new("boom") }

    before do
      allow(UsageAttributionValues::TrackService).to receive(:call!).with(organization:, entries: anything).and_raise(error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports the error and still tracks the other organizations" do
      expect { consumer.consume }.not_to raise_error

      expect(Sentry).to have_received(:capture_exception).with(error, extra: {organization_id: organization.id})
      expect(UsageAttributionValues::TrackService).to have_received(:call!).with(organization: other_organization, entries: [messages[1]])
    end
  end
end
