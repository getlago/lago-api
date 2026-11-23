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

  context "when the shadow organization has a discarded feature with the same code" do
    before_all { create(:feature, organization: shadow_organization, code: "seats").discard! }

    it "creates a new one" do
      expect(result.created_features).to eq(%w[seats sso])
      expect(shadow_features.map(&:first)).to eq(%w[seats sso])
    end
  end

  context "when a shadow privilege has another value type" do
    before_all do
      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      create(:privilege, feature: shadow_seats, code: "max", value_type: "string")
    end

    it "fails without creating anything" do
      expect { result }.not_to change { Entitlement::Privilege.unscoped.count }

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({"seats.max": ["value_type_mismatch"]})
      expect(shadow_features.map(&:first)).to eq(%w[seats])
    end
  end

  context "when a shadow select privilege has other options" do
    before_all do
      shadow_seats = create(:feature, organization: shadow_organization, code: "seats")
      create(:privilege, feature: shadow_seats, code: "tier", value_type: "select", config: {select_options: %w[gold]})
    end

    it "fails without creating anything" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"seats.tier": ["select_options_mismatch"]})
      expect(shadow_features.map(&:first)).to eq(%w[seats])
    end
  end
end
