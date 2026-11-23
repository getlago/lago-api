# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::Lookup do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:other_organization) { create(:organization) }

  let(:status) { "shadowing" }
  let(:migration) do
    create(:billing_engine_migration, organization:, shadow_organization:, status:, plan_mapping: {"legacy" => "catalog"})
  end

  before { migration }

  describe ".for_source" do
    it "returns the shadowing migration of the source organization" do
      expect(described_class.for_source(organization.id)).to have_attributes(
        id: migration.id,
        organization_id: organization.id,
        shadow_organization_id: shadow_organization.id,
        status: "shadowing",
        plan_mapping: {"legacy" => "catalog"}
      )
    end

    it "returns a frozen entry" do
      entry = described_class.for_source(organization.id)

      expect(entry).to be_frozen
      expect(entry.plan_mapping).to be_frozen
      expect(entry.plan_mapping.values).to all(be_frozen)
    end

    it { expect(described_class.for_source(shadow_organization.id)).to be_nil }
    it { expect(described_class.for_source(other_organization.id)).to be_nil }

    context "when the migration is paused" do
      let(:status) { "paused" }

      it { expect(described_class.for_source(organization.id)).to be_nil }
    end

    context "when the migration is aborted" do
      let(:status) { "aborted" }

      it { expect(described_class.for_source(organization.id)).to be_nil }
    end
  end

  describe ".for_shadow" do
    it "returns the migration of the shadow organization" do
      expect(described_class.for_shadow(shadow_organization.id)).to have_attributes(id: migration.id, status: "shadowing")
    end

    it { expect(described_class.for_shadow(organization.id)).to be_nil }
    it { expect(described_class.for_shadow(other_organization.id)).to be_nil }

    context "when the migration is paused" do
      let(:status) { "paused" }

      it { expect(described_class.for_shadow(shadow_organization.id)).to have_attributes(id: migration.id, status: "paused") }
    end

    context "when the migration is aborted" do
      let(:status) { "aborted" }

      it { expect(described_class.for_shadow(shadow_organization.id)).to be_nil }
    end
  end

  describe ".shadow_organization?" do
    it { expect(described_class.shadow_organization?(shadow_organization.id)).to be(true) }
    it { expect(described_class.shadow_organization?(organization.id)).to be(false) }
    it { expect(described_class.shadow_organization?(other_organization.id)).to be(false) }

    context "when the migration is aborted" do
      let(:status) { "aborted" }

      it { expect(described_class.shadow_organization?(shadow_organization.id)).to be(false) }
    end
  end

  describe "snapshot" do
    before { described_class.for_source(organization.id) }

    it "answers hits and misses without a query once loaded" do
      statements = capture_sql do
        described_class.for_source(organization.id)
        described_class.for_source(other_organization.id)
        described_class.for_shadow(shadow_organization.id)
        described_class.shadow_organization?(other_organization.id)
      end

      expect(statements).to be_empty
    end

    context "when a row changes without callbacks" do
      before { migration.update_columns(status: "paused") } # rubocop:disable Rails/SkipsModelValidations

      it "keeps the loaded snapshot until the refresh interval" do
        travel(described_class::REFRESH_INTERVAL - 1.second) do
          expect(described_class.for_source(organization.id)).to have_attributes(id: migration.id)
        end
      end

      it "reloads it after the refresh interval with one query" do
        travel(described_class::REFRESH_INTERVAL) do
          statements = capture_sql { expect(described_class.for_source(organization.id)).to be_nil }

          expect(statements.size).to eq(1)
          expect(described_class.for_shadow(shadow_organization.id)).to have_attributes(status: "paused")
        end
      end
    end

    it "reloads after a migration is created" do
      expect { create(:billing_engine_migration, organization: other_organization) }
        .to change { described_class.for_source(other_organization.id) }.from(nil).to(be_present)
    end

    it "reloads after a migration is updated" do
      expect { migration.update!(status: "paused") }
        .to change { described_class.for_source(organization.id) }.from(be_present).to(nil)
    end

    it "reloads after a migration is destroyed" do
      expect { migration.destroy! }
        .to change { described_class.shadow_organization?(shadow_organization.id) }.from(true).to(false)
    end
  end

  context "when the snapshot is loaded inside a transaction that rolls back" do
    it "drops the rolled back row" do
      ActiveRecord::Base.transaction(requires_new: true) do
        create(:billing_engine_migration, organization: other_organization)
        expect(described_class.for_source(other_organization.id)).to be_present
        raise ActiveRecord::Rollback
      end

      expect(described_class.for_source(other_organization.id)).to be_nil
    end
  end

  describe ".expire!" do
    before { described_class.for_source(organization.id) }

    it "makes the next read load the rows again" do
      described_class.expire!

      expect(capture_sql { described_class.for_source(organization.id) }.size).to eq(1)
    end
  end
end
