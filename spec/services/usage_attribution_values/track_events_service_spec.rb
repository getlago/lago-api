# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValues::TrackEventsService do
  subject(:track) { described_class.call(organization:, events:) }

  let(:organization) { create(:organization, feature_flags: ["account_tree"]) }
  let(:department) { create(:usage_attribution_type, organization:, code: "department", attribution_keys: ["department_id"]) }
  let(:timestamp) { Time.zone.parse("2026-10-09T10:00:00.123456Z") }
  let(:events) { [build_event("sub_1", {"department_id" => "rnd", "tokens" => 10})] }
  let(:shared_cache) { ActiveSupport::Cache::MemoryStore.new }

  def build_event(external_subscription_id, properties, at: timestamp)
    Event.new(organization_id: organization.id, external_subscription_id:, properties:, timestamp: at)
  end

  before do
    department
    allow(Rails).to receive(:cache).and_return(shared_cache)
  end

  it "enqueues the combinations seen for the first time" do
    expect { track }.to have_enqueued_job(UsageAttributionValues::TrackJob).with(
      organization,
      [{"external_subscription_id" => "sub_1", "labels" => {"department" => "rnd"}, "seen_at" => "2026-10-09T10:00:00.123456Z"}]
    )
  end

  context "when a combination was already seen" do
    before { described_class.call(organization:, events:) }

    it "does not enqueue it again" do
      expect { track }.not_to have_enqueued_job(UsageAttributionValues::TrackJob)
    end
  end

  context "with several combinations" do
    let(:events) { (1..3).map { build_event("sub_#{it}", {"department_id" => "rnd"}) } }

    before { allow(shared_cache).to receive(:read_multi).and_call_original }

    it "checks them in the shared cache at once" do
      track

      expect(shared_cache).to have_received(:read_multi).once
    end
  end

  context "when a usage attribution type was created since the types were cached" do
    let(:team) { create(:usage_attribution_type, organization:, code: "team", attribution_keys: ["team_id"]) }
    let(:events) { [build_event("sub_1", {"team_id" => "eng"})] }

    before do
      described_class.call(organization:, events:)
      team
    end

    it "does not track its values yet" do
      expect { track }.not_to have_enqueued_job(UsageAttributionValues::TrackJob)
    end

    context "when the cached types expired" do
      before { travel(described_class::TYPES_TTL + 1.second) }

      it "tracks its values" do
        expect { track }.to have_enqueued_job(UsageAttributionValues::TrackJob)
      end
    end
  end

  context "with the same combination several times in the request" do
    let(:events) do
      [
        build_event("sub_1", {"department_id" => "rnd"}),
        build_event("sub_1", {"department_id" => "rnd"}, at: timestamp + 1.minute),
        build_event("sub_2", {"department_id" => "rnd"})
      ]
    end

    it "enqueues each combination once, with its latest timestamp" do
      expect { track }.to have_enqueued_job(UsageAttributionValues::TrackJob).with(
        organization,
        [
          {"external_subscription_id" => "sub_1", "labels" => {"department" => "rnd"}, "seen_at" => (timestamp + 1.minute).iso8601(6)},
          {"external_subscription_id" => "sub_2", "labels" => {"department" => "rnd"}, "seen_at" => timestamp.iso8601(6)}
        ]
      )
    end
  end

  context "when the events carry no attribution key" do
    let(:events) { [build_event("sub_1", {"tokens" => 10})] }

    it "does not enqueue anything" do
      expect { track }.not_to have_enqueued_job(UsageAttributionValues::TrackJob)
    end
  end

  context "when the organization has no usage attribution types" do
    let(:department) { nil }

    it "does not enqueue anything" do
      expect { track }.not_to have_enqueued_job(UsageAttributionValues::TrackJob)
    end
  end

  context "when the account_tree feature flag is disabled" do
    let(:organization) { create(:organization) }

    it "does not enqueue anything" do
      expect { track }.not_to have_enqueued_job(UsageAttributionValues::TrackJob)
    end
  end

  context "when tracking fails" do
    let(:error) { StandardError.new("cache unavailable") }

    before do
      allow(UsageAttributions::LabelsService).to receive(:call).and_raise(error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports the error without failing" do
      expect(track).to be_success
      expect(Sentry).to have_received(:capture_exception).with(error, extra: {organization_id: organization.id})
    end
  end
end
