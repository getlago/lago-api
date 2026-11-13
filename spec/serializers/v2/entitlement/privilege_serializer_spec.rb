# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Entitlement::PrivilegeSerializer do
  subject(:payload) { described_class.new(privilege, includes:).serialize }

  let(:feature) { build_stubbed(:feature, code: "sso") }
  let(:privilege) do
    build_stubbed(
      :privilege,
      value_type_trait,
      feature:,
      code: "max_users",
      name: "Max users",
      created_at: Time.zone.parse("2026-03-02T10:00:00.123456Z"),
      updated_at: Time.zone.parse("2026-03-04T12:30:00.654321Z"),
      deleted_at:
    )
  end
  let(:value_type_trait) { :integer_type }
  let(:deleted_at) { nil }
  let(:includes) { [] }
  let(:expected_payload) do
    {
      lago_id: privilege.id,
      feature_code: "sso",
      code: "max_users",
      name: "Max users",
      value_type: "integer",
      select_options: nil,
      created_at: "2026-03-02T10:00:00Z",
      updated_at: "2026-03-04T12:30:00Z",
      deleted_at: nil
    }
  end

  it "renders the privilege with whole-second timestamps and no select options" do
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

  context "with a string privilege" do
    let(:value_type_trait) { :string_type }

    it "renders no select options" do
      expect(payload).to eq(expected_payload.merge(value_type: "string", select_options: nil))
    end
  end

  context "with a boolean privilege" do
    let(:value_type_trait) { :boolean_type }

    it "renders no select options" do
      expect(payload).to eq(expected_payload.merge(value_type: "boolean", select_options: nil))
    end
  end

  context "with a select privilege" do
    let(:privilege) do
      build_stubbed(
        :privilege,
        :select_type,
        feature:,
        code: "max_users",
        name: "Max users",
        config: {"select_options" => ["okta", "google"]},
        created_at: Time.zone.parse("2026-03-02T10:00:00.123456Z"),
        updated_at: Time.zone.parse("2026-03-04T12:30:00.654321Z")
      )
    end

    it "renders its select options" do
      expect(payload).to eq(expected_payload.merge(value_type: "select", select_options: ["okta", "google"]))
    end
  end

  context "with a string privilege whose config still holds select options" do
    # Rows written before the config validation can hold options for another value type.
    let(:privilege) do
      build_stubbed(
        :privilege,
        :string_type,
        feature:,
        code: "max_users",
        name: "Max users",
        config: {"select_options" => ["okta"]},
        created_at: Time.zone.parse("2026-03-02T10:00:00.123456Z"),
        updated_at: Time.zone.parse("2026-03-04T12:30:00.654321Z")
      )
    end

    it "renders no select options" do
      expect(payload).to eq(expected_payload.merge(value_type: "string", select_options: nil))
    end
  end

  context "when the privilege is discarded" do
    let(:deleted_at) { Time.zone.parse("2026-03-05T08:15:00Z") }

    it "renders its deletion timestamp" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-03-05T08:15:00Z"))
    end
  end
end
