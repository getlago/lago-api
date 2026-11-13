# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Entitlement::FeatureSerializer do
  subject(:payload) { described_class.new(feature, includes:).serialize }

  let(:feature) do
    build_stubbed(
      :feature,
      code: "seats",
      name: "Seats",
      description: "Number of seats",
      created_at: Time.zone.parse("2026-03-02T10:00:00.123456Z"),
      updated_at: Time.zone.parse("2026-03-04T12:30:00.654321Z"),
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:includes) { [] }
  let(:expected_payload) do
    {
      lago_id: feature.id,
      code: "seats",
      name: "Seats",
      description: "Number of seats",
      created_at: "2026-03-02T10:00:00Z",
      updated_at: "2026-03-04T12:30:00Z",
      deleted_at: nil
    }
  end

  it "renders the feature with whole-second timestamps" do
    expect(payload).to eq(expected_payload)
  end

  context "with microsecond timestamps" do
    let(:includes) { %i[usec_timestamps] }

    it "renders the timestamps to the microsecond" do
      expect(payload).to eq(expected_payload.merge(
        created_at: "2026-03-02T10:00:00.123456Z",
        updated_at: "2026-03-04T12:30:00.654321Z"
      ))
    end
  end

  context "with privileges" do
    let(:feature) { create(:feature, code: "seats", name: "Seats", description: "Number of seats") }
    let(:expected_payload) do
      {
        lago_id: feature.id,
        code: "seats",
        name: "Seats",
        description: "Number of seats",
        created_at: feature.created_at.iso8601,
        updated_at: feature.updated_at.iso8601,
        deleted_at: nil
      }
    end

    before { create(:privilege, feature:, organization: feature.organization) }

    it "renders neither the privileges nor a count of them" do
      expect(payload).to eq(expected_payload)
    end
  end

  context "with the privileges expanded" do
    let(:feature) { create(:feature, code: "seats", name: "Seats", description: "Number of seats") }
    let(:includes) { %i[privileges] }
    let(:first_at) { Time.zone.parse("2026-03-02T10:00:00Z") }
    let(:second_at) { Time.zone.parse("2026-03-03T10:00:00Z") }
    let(:select_privilege) do
      create(:privilege, :select_type, feature:, code: "bbb", name: "Tier", created_at: second_at, updated_at: second_at)
    end
    let(:tied_privileges) do
      # Same created_at, inserted and named against the id order, so only the id breaks the tie.
      [
        create(:privilege, :boolean_type, feature:, id: "00000000-0000-0000-0000-000000000002", code: "aaa", name: nil, created_at: first_at, updated_at: first_at),
        create(:privilege, :integer_type, feature:, id: "00000000-0000-0000-0000-000000000001", code: "zzz", name: "Max", created_at: first_at, updated_at: first_at)
      ].reverse
    end
    let(:discarded_privilege) do
      create(:privilege, feature:, code: "old", created_at: first_at - 1.day, deleted_at: first_at)
    end

    before do
      select_privilege
      tied_privileges
      discarded_privilege
    end

    it "renders the live privileges oldest first, then by id" do
      expect(payload).to eq(
        lago_id: feature.id,
        code: "seats",
        name: "Seats",
        description: "Number of seats",
        created_at: feature.created_at.iso8601,
        updated_at: feature.updated_at.iso8601,
        deleted_at: nil,
        privileges: [
          *tied_privileges.map do |privilege|
            {
              lago_id: privilege.id,
              feature_code: "seats",
              code: privilege.code,
              name: privilege.name,
              value_type: privilege.value_type,
              select_options: nil,
              created_at: "2026-03-02T10:00:00Z",
              updated_at: "2026-03-02T10:00:00Z",
              deleted_at: nil
            }
          end,
          {
            lago_id: select_privilege.id,
            feature_code: "seats",
            code: "bbb",
            name: "Tier",
            value_type: "select",
            select_options: %w[option1 option2 option3],
            created_at: "2026-03-03T10:00:00Z",
            updated_at: "2026-03-03T10:00:00Z",
            deleted_at: nil
          }
        ]
      )
    end

    it "does not load the feature once per privilege" do
      tables = []
      callback = ->(*, payload) { tables << payload[:sql][/FROM "(entitlement_features|entitlement_privileges)"/, 1] }
      serializer = described_class.new(Entitlement::Feature.find(feature.id), includes:)

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { serializer.serialize }

      expect(tables.compact.tally).to eq("entitlement_privileges" => 1)
    end

    context "when the feature has no privileges" do
      let(:select_privilege) { nil }
      let(:tied_privileges) { [] }
      let(:discarded_privilege) { nil }

      it "renders an empty list" do
        expect(payload).to eq(
          lago_id: feature.id,
          code: "seats",
          name: "Seats",
          description: "Number of seats",
          created_at: feature.created_at.iso8601,
          updated_at: feature.updated_at.iso8601,
          deleted_at: nil,
          privileges: []
        )
      end
    end
  end

  context "when the feature is discarded" do
    let(:deleted_at) { Time.zone.parse("2026-03-05T08:15:00Z") }

    it "renders its deletion timestamp" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-03-05T08:15:00Z"))
    end
  end
end
