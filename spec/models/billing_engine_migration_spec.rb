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
      expect(migration).to define_enum_for(:events_copy_source)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(api: "api", raw_topic: "raw_topic")
        .with_prefix(:events_copied_from)
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

    describe "events_copy_source validation" do
      subject(:migration) { create(:billing_engine_migration, status:) }

      before { migration.events_copy_source = "raw_topic" }

      context "when the migration is shadowing" do
        let(:status) { "shadowing" }

        it "refuses to switch the source" do
          expect(migration).not_to be_valid
          expect(migration.errors.where(:events_copy_source, :invalid)).to be_present
        end
      end

      context "when the migration is paused" do
        let(:status) { "paused" }

        it { expect(migration).to be_valid }

        it "refuses to switch the source and resume at once" do
          migration.status = "shadowing"

          expect(migration).not_to be_valid
        end
      end

      context "when the migration is created with it" do
        subject(:migration) { build(:billing_engine_migration) }

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
