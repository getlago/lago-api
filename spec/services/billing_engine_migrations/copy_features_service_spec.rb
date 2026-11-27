# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyFeaturesService do
  subject(:result) { described_class.call(migration:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:migration) { create(:billing_engine_migration, organization:, shadow_organization:) }
  let_it_be(:seats) { create(:feature, organization:, code: "seats", name: "Seats", description: "Seat limits") }
  let_it_be(:sso) { create(:feature, organization:, code: "sso", name: "SSO", description: nil) }

  before_all do
    create(:privilege, feature: seats, code: "max", name: "Max", value_type: "integer")
    create(:privilege, feature: seats, code: "tier", value_type: "select", config: {select_options: %w[silver gold]})
    create(:feature, organization:, code: "removed").discard!
    create(:feature, code: "other_organization")
  end

  def shadow_features
    shadow_organization.features.order(:code).pluck(:code, :name, :description)
  end

  def shadow_privileges
    shadow_organization.privileges.joins(:feature).order(:code)
      .pluck("entitlement_features.code", :code, :name, :value_type, :config)
  end

  it "creates the features and privileges of the organization in the shadow organization" do
    expect(result).to be_success
    expect(result.created_features).to eq(%w[seats sso])
    expect(result.created_privileges).to eq(%w[seats.max seats.tier])
    expect(result.updated_privileges).to eq([])

    expect(shadow_features).to eq([["seats", "Seats", "Seat limits"], ["sso", "SSO", nil]])
    expect(shadow_privileges).to eq(
      [
        ["seats", "max", "Max", "integer", {}],
        ["seats", "tier", nil, "select", {"select_options" => %w[silver gold]}]
      ]
    )
  end

  it "returns the shadow features by code with their privileges" do
    expect(result.features.keys).to match_array(%w[seats sso])
    expect(result.features.values.map(&:organization_id).uniq).to eq([shadow_organization.id])
    expect(result.features["seats"].privileges.map(&:code)).to match_array(%w[max tier])
    expect(result.features["sso"].privileges).to be_empty
  end

  it "creates nothing on a second run" do
    described_class.call(migration:)

    expect { result }
      .to not_change { Entitlement::Feature.unscoped.count }
      .and not_change { Entitlement::Privilege.unscoped.count }

    expect(result.created_features).to eq([])
    expect(result.created_privileges).to eq([])
    expect(result.updated_privileges).to eq([])
  end

  context "when a feature is created in the shadow organization between the read and the insert" do
    before do
      allow(Entitlement::Feature).to receive(:insert_all).and_wrap_original do |original, *args, **kwargs|
        create(:feature, organization: shadow_organization, code: "sso")
        original.call(*args, **kwargs)
      end
    end

    it "reports only the features it inserted" do
      expect(result.created_features).to eq(%w[seats])
      expect(shadow_features.map(&:first)).to eq(%w[seats sso])
    end
  end

  context "when the shadow organization already has some of them" do
    let_it_be(:shadow_seats) { create(:feature, organization: shadow_organization, code: "seats", name: "Renamed") }

    before_all { create(:privilege, feature: shadow_seats, code: "max", value_type: "integer") }

    it "creates only the missing ones and leaves the existing ones as they are" do
      expect(result.created_features).to eq(%w[sso])
      expect(result.created_privileges).to eq(%w[seats.tier])

      expect(shadow_features).to eq([["seats", "Renamed", "Feature Description"], ["sso", "SSO", nil]])
      expect(shadow_privileges.map { it.first(2) }).to eq([%w[seats max], %w[seats tier]])
      expect(result.features["seats"]).to eq(shadow_seats)
    end
  end

  context "when the shadow organization has a feature the organization does not have" do
    before_all { create(:feature, organization: shadow_organization, code: "legacy") }

    it "returns it with the copied features" do
      expect(result.created_features).to eq(%w[seats sso])
      expect(result.features.keys).to match_array(%w[legacy seats sso])
    end
  end

  context "when the shadow organization has a discarded feature with the same code" do
    before_all { create(:feature, organization: shadow_organization, code: "seats").discard! }

    it "creates a new one" do
      expect(result.created_features).to eq(%w[seats sso])
      expect(shadow_features.map(&:first)).to eq(%w[seats sso])
    end
  end

  context "when a shadow privilege has another value type" do
    let_it_be(:shadow_seats) { create(:feature, organization: shadow_organization, code: "seats") }
    let_it_be(:shadow_max) { create(:privilege, feature: shadow_seats, code: "max", value_type: "string") }
    let_it_be(:shadow_max_value) do
      shadow_plan = create(:plan, organization: shadow_organization)
      create(:entitlement_value, entitlement: create(:entitlement, plan: shadow_plan, feature: shadow_seats), privilege: shadow_max, value: "ten")
    end

    it "discards it with its values and copies the organization one" do
      expect(result).to be_success
      expect(result.removed_privileges).to eq(%w[seats.max])
      expect(result.created_privileges).to eq(%w[seats.max seats.tier])

      expect(Entitlement::Privilege.unscoped.find(shadow_max.id)).to be_discarded
      expect(Entitlement::EntitlementValue.unscoped.find(shadow_max_value.id)).to be_discarded
      expect(shadow_privileges).to include(["seats", "max", "Max", "integer", {}])
    end
  end

  context "when the organization removed a privilege copied before" do
    let_it_be(:shadow_seats) { create(:feature, organization: shadow_organization, code: "seats") }
    let_it_be(:shadow_legacy) { create(:privilege, feature: shadow_seats, code: "legacy", value_type: "boolean") }

    it "discards it" do
      expect(result).to be_success
      expect(result.removed_privileges).to eq(%w[seats.legacy])
      expect(Entitlement::Privilege.unscoped.find(shadow_legacy.id)).to be_discarded
      expect(shadow_privileges.map(&:second)).to eq(%w[max tier])
    end
  end

  context "when a shadow select privilege lacks options added in the organization since the last copy" do
    let_it_be(:shadow_seats) { create(:feature, organization: shadow_organization, code: "seats") }
    let_it_be(:shadow_tier, refind: true) do
      create(:privilege, feature: shadow_seats, code: "tier", value_type: "select", config: {select_options: %w[silver]})
    end

    it "updates its select options to the organization ones" do
      expect(result).to be_success
      expect(result.created_privileges).to eq(%w[seats.max])
      expect(result.updated_privileges).to eq(%w[seats.tier])

      expect(shadow_tier.reload.config).to eq({"select_options" => %w[silver gold]})
      expect(result.features["seats"].privileges.find { it.code == "tier" }.config).to eq({"select_options" => %w[silver gold]})
    end
  end

  context "when a shadow select privilege has an option the organization does not have" do
    before_all do
      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      create(:privilege, feature: shadow_seats, code: "tier", value_type: "select", config: {select_options: %w[gold bronze]})
    end

    it "discards it and copies the organization one" do
      expect(result).to be_success
      expect(result.removed_privileges).to eq(%w[seats.tier])
      expect(result.updated_privileges).to be_empty
      expect(shadow_privileges).to include(["seats", "tier", nil, "select", {"select_options" => %w[silver gold]}])
    end
  end
end
