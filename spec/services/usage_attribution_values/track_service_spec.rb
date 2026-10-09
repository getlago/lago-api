# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValues::TrackService do
  subject(:track) { described_class.call!(organization:, entries:) }

  let(:organization) { create(:organization, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:, external_id: "sub_1", started_at: 1.month.ago) }

  let(:department) { create(:usage_attribution_type, organization:, code: "department", attribution_keys: ["department_id"]) }
  let(:team) { create(:usage_attribution_type, organization:, code: "team", attribution_keys: ["team_id"], parent: department) }
  let(:user) { create(:usage_attribution_type, organization:, code: "user", attribution_keys: ["user_id"], parent: team) }
  let(:model) { create(:flat_usage_attribution_type, organization:, code: "model", attribution_keys: ["model"]) }

  let(:seen_at) { Time.zone.parse("2026-10-09T10:00:00Z") }
  let(:labels) { {"department" => "rnd", "team" => "eng", "user" => "alice", "model" => "opus"} }
  let(:entries) { [entry(labels)] }

  def entry(labels, at: seen_at, external_subscription_id: "sub_1")
    {"external_subscription_id" => external_subscription_id, "labels" => labels, "seen_at" => at.iso8601(6)}
  end

  def value_of(attribution_type, value)
    UsageAttributionValue.with_discarded.find_by(customer:, usage_attribution_type: attribution_type, value:)
  end

  before do
    subscription
    [department, team, user, model]
  end

  it "creates the values of the chain linked to their parents, and the flat values as roots" do
    track

    rnd = value_of(department, "rnd")
    eng = value_of(team, "eng")
    alice = value_of(user, "alice")
    opus = value_of(model, "opus")

    expect([rnd, eng, alice, opus].map(&:parent_id)).to eq([nil, rnd.id, eng.id, nil])
    expect([rnd, eng, alice, opus].map(&:last_seen_at)).to all(eq(seen_at))
    expect([rnd, eng, alice, opus].map(&:organization_id)).to all(eq(organization.id))
  end

  context "when the chain is partial" do
    let(:labels) { {"department" => "rnd", "user" => "alice"} }

    it "creates the values without the missing parent" do
      track

      expect(value_of(department, "rnd").parent_id).to be_nil
      expect(value_of(user, "alice").parent_id).to be_nil
      expect(UsageAttributionValue.count).to eq(2)
    end
  end

  context "when the same values are tracked again" do
    before { described_class.call!(organization:, entries:) }

    it "does not duplicate them" do
      expect { track }.not_to change(UsageAttributionValue, :count)
    end
  end

  context "when a value was seen more recently" do
    before { described_class.call!(organization:, entries: [entry(labels, at: seen_at + 1.day)]) }

    it "keeps the latest last_seen_at" do
      track

      expect(value_of(user, "alice").last_seen_at).to eq(seen_at + 1.day)
    end
  end

  context "when a value is seen later" do
    before { described_class.call!(organization:, entries: [entry(labels, at: seen_at - 1.day)]) }

    it "moves last_seen_at forward" do
      track

      expect(value_of(user, "alice").last_seen_at).to eq(seen_at)
    end
  end

  context "when a value moves under another parent" do
    let(:entries) { [entry(labels.merge("team" => "data"))] }

    before { described_class.call!(organization:, entries: [entry(labels)]) }

    it "keeps its first parent" do
      track

      expect(value_of(user, "alice").parent_id).to eq(value_of(team, "eng").id)
    end
  end

  context "when a value was discarded" do
    before do
      described_class.call!(organization:, entries:)
      value_of(user, "alice").discard!
    end

    it "restores it" do
      track

      expect(value_of(user, "alice")).not_to be_discarded
    end
  end

  context "with several entries holding the same value" do
    let(:entries) do
      [
        entry({"department" => "rnd", "team" => "eng"}),
        entry({"department" => "rnd", "team" => "data"}, at: seen_at + 1.hour)
      ]
    end

    it "upserts it once, with the latest last_seen_at" do
      track

      expect(UsageAttributionValue.where(usage_attribution_type: department).count).to eq(1)
      expect(value_of(department, "rnd").last_seen_at).to eq(seen_at + 1.hour)
      expect(value_of(team, "data").parent_id).to eq(value_of(department, "rnd").id)
    end
  end

  context "with a label of a deleted or unknown type" do
    let(:labels) { {"model" => "opus", "region" => "eu"} }

    before { model.discard! }

    it "skips it" do
      expect { track }.not_to change(UsageAttributionValue, :count)
    end
  end

  context "when the parent type was deleted" do
    let(:labels) { {"department" => "rnd", "team" => "eng"} }

    before { department.discard! }

    it "creates the child as a root" do
      track

      expect(value_of(team, "eng").parent_id).to be_nil
      expect(value_of(department, "rnd")).to be_nil
    end
  end

  context "when no subscription matches" do
    let(:entries) { [entry(labels, external_subscription_id: "unknown")] }

    it "skips the entry" do
      expect { track }.not_to change(UsageAttributionValue, :count)
    end
  end

  context "when the subscription belongs to another organization" do
    before { create(:subscription, external_id: "sub_other", started_at: 1.month.ago) }

    let(:entries) { [entry(labels, external_subscription_id: "sub_other")] }

    it "skips the entry" do
      expect { track }.not_to change(UsageAttributionValue, :count)
    end
  end

  context "when the subscription started after the event" do
    let(:entries) { [entry(labels, at: 2.months.ago)] }

    it "skips the entry" do
      expect { track }.not_to change(UsageAttributionValue, :count)
    end
  end
end
