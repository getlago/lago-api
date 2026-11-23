# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigration do
  subject(:migration) { build(:billing_engine_migration) }

  describe "enums" do
    it do
      expect(migration).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(shadowing: "shadowing", paused: "paused", aborted: "aborted")
    end
  end

  describe "associations" do
    it do
      expect(migration).to belong_to(:organization)
      expect(migration).to belong_to(:shadow_organization).class_name("Organization")
    end
  end

  describe "validations" do
    it { expect(migration).to be_valid }

    describe "shadow_organization validation" do
      before { migration.shadow_organization = migration.organization }

      it "rejects the organization itself as its shadow" do
        expect(migration).not_to be_valid
        expect(migration.errors.where(:shadow_organization, :invalid)).to be_present
      end
    end

    describe "organizations validation" do
      let(:other_migration) { create(:billing_engine_migration) }

      context "when the organization is the shadow of another migration" do
        before { migration.organization = other_migration.shadow_organization }

        it "rejects it" do
          expect(migration).not_to be_valid
          expect(migration.errors.where(:organization, :value_already_exist)).to be_present
        end
      end

      context "when the shadow organization is migrated by another migration" do
        before { migration.shadow_organization = other_migration.organization }

        it "rejects it" do
          expect(migration).not_to be_valid
          expect(migration.errors.where(:shadow_organization, :value_already_exist)).to be_present
        end
      end

      context "when the migration is saved again" do
        subject(:migration) { create(:billing_engine_migration) }

        it { expect(migration).to be_valid }
      end
    end

    describe "plan_mapping validation" do
      before { migration.plan_mapping = plan_mapping }

      context "with plan codes mapped to catalog plan codes" do
        let(:plan_mapping) { {"legacy_plan" => "catalog_plan"} }

        it { expect(migration).to be_valid }
      end

      context "with an empty mapping" do
        let(:plan_mapping) { {} }

        it { expect(migration).to be_valid }
      end

      context "when it is not a hash" do
        let(:plan_mapping) { ["legacy_plan"] }

        it { expect(migration).not_to be_valid }
      end

      context "when a key is blank" do
        let(:plan_mapping) { {"" => "catalog_plan"} }

        it { expect(migration).not_to be_valid }
      end

      context "when a value is blank" do
        let(:plan_mapping) { {"legacy_plan" => ""} }

        it { expect(migration).not_to be_valid }
      end

      context "when a value is not a string" do
        let(:plan_mapping) { {"legacy_plan" => 1} }

        it { expect(migration).not_to be_valid }
      end
    end

    describe "v2_read_endpoints validation" do
      before { migration.v2_read_endpoints = v2_read_endpoints }

      context "with native v2 endpoints" do
        let(:v2_read_endpoints) { %w[contracts contracts/usage customers] }

        it { expect(migration).to be_valid }
      end

      context "with no endpoint" do
        let(:v2_read_endpoints) { [] }

        it { expect(migration).to be_valid }
      end

      context "with an endpoint that v1 serves under /api/v2" do
        let(:v2_read_endpoints) { %w[contracts subscriptions] }

        it "rejects it" do
          expect(migration).not_to be_valid
          expect(migration.errors.where(:v2_read_endpoints, :invalid)).to be_present
        end
      end

      context "with an unknown endpoint" do
        let(:v2_read_endpoints) { %w[contracts/current_usage] }

        it { expect(migration).not_to be_valid }
      end
    end
  end

  describe ".v2_endpoint" do
    it { expect(described_class.v2_endpoint("api/v2/contracts/usage")).to eq("contracts/usage") }
    it { expect(described_class.v2_endpoint("api/v1/subscriptions")).to be_nil }
    it { expect(described_class.v2_endpoint(nil)).to be_nil }
  end

  describe ".native_v2_endpoints" do
    it "lists the controllers of the native v2 routes only" do
      expect(described_class.native_v2_endpoints).to include("contracts", "contracts/usage", "customers", "events")
      expect(described_class.native_v2_endpoints).not_to include("subscriptions", "application", nil)
    end
  end

  describe "#shadow_organization_isolated?" do
    subject(:migration) { create(:billing_engine_migration) }

    let(:shadow_organization) { migration.shadow_organization }

    it { expect(migration).to be_shadow_organization_isolated }

    context "when the shadow organization has a webhook endpoint" do
      before { create(:webhook_endpoint, organization: shadow_organization) }

      it { expect(migration).not_to be_shadow_organization_isolated }
    end

    context "when a billing entity of the shadow organization has email settings" do
      before { create(:billing_entity, organization: shadow_organization, email_settings: ["invoice.finalized"]) }

      it { expect(migration).not_to be_shadow_organization_isolated }
    end

    context "when a billing entity of the shadow organization has a dunning campaign" do
      before do
        create(
          :billing_entity,
          organization: shadow_organization,
          email_settings: [],
          applied_dunning_campaign: create(:dunning_campaign, organization: shadow_organization)
        )
      end

      it { expect(migration).not_to be_shadow_organization_isolated }
    end

    context "when a customer of the shadow organization has a dunning campaign" do
      before do
        create(
          :customer,
          organization: shadow_organization,
          applied_dunning_campaign: create(:dunning_campaign, organization: shadow_organization)
        )
      end

      it { expect(migration).not_to be_shadow_organization_isolated }
    end

    context "when only the v1 organization has outbound settings" do
      before { create(:webhook_endpoint, organization: migration.organization) }

      it { expect(migration).to be_shadow_organization_isolated }
    end
  end
end
