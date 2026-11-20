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
end
