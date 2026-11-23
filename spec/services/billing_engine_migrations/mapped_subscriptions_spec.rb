# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::MappedSubscriptions do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:mapped_plan) { create(:plan, organization:, code: "legacy") }
  let_it_be(:override_plan) { create(:plan, organization:, code: "legacy", parent: mapped_plan) }
  let_it_be(:unmapped_plan) { create(:plan, organization:, code: "other") }

  let_it_be(:mapped_subscription, refind: true) { create(:subscription, customer:, plan: mapped_plan, external_id: "mapped") }
  let_it_be(:override_subscription) { create(:subscription, customer:, plan: override_plan, external_id: "override") }
  let_it_be(:unmapped_subscription) { create(:subscription, customer:, plan: unmapped_plan, external_id: "unmapped") }
  let_it_be(:terminated_subscription) { create(:subscription, :terminated, customer:, plan: mapped_plan, external_id: "terminated") }
  let_it_be(:other_organization_subscription) do
    other_organization = create(:organization)
    create(
      :subscription,
      customer: create(:customer, organization: other_organization),
      plan: create(:plan, organization: other_organization, code: "legacy"),
      external_id: "elsewhere"
    )
  end

  let(:plan_mapping) { {"legacy" => "catalog"} }
  let(:migration) do
    create(:billing_engine_migration, organization:, shadow_organization:, plan_mapping:)
    BillingEngineMigrations::Lookup.for_source(organization.id)
  end

  let(:external_ids) { %w[mapped override unmapped terminated elsewhere unknown] }

  describe ".filter" do
    it "keeps the active subscriptions on a mapped plan that is not an override" do
      expect(described_class.filter(migration, external_ids)).to eq(Set["mapped"])
    end

    it "answers the ids it has seen without a query" do
      described_class.filter(migration, external_ids)

      statements = capture_sql { described_class.filter(migration, external_ids) }

      expect(statements).to be_empty
    end

    context "when a subscription is created after the snapshot is loaded" do
      before { described_class.filter(migration, external_ids) }

      it "finds it on its first event with one query" do
        create(:subscription, customer:, plan: mapped_plan, external_id: "new")

        statements = capture_sql { expect(described_class.filter(migration, %w[mapped new])).to eq(Set["mapped", "new"]) }

        expect(statements.size).to eq(1)
      end
    end

    context "when an unmapped id was already looked up" do
      before { described_class.filter(migration, external_ids) }

      it "does not look it up again before the refresh" do
        create(:subscription, customer:, plan: mapped_plan, external_id: "unknown")

        travel(described_class::REFRESH_INTERVAL - 1.second) do
          expect(described_class.filter(migration, ["unknown"])).to be_empty
        end
      end

      it "reloads the snapshot after the refresh interval" do
        create(:subscription, customer:, plan: mapped_plan, external_id: "unknown")
        mapped_subscription.update!(status: :terminated, terminated_at: Time.current)

        travel(described_class::REFRESH_INTERVAL + 1.second) do
          expect(described_class.filter(migration, external_ids)).to eq(Set["unknown"])
        end
      end
    end

    context "when the plan mapping changes" do
      before { described_class.filter(migration, external_ids) }

      it "reloads the snapshot at once" do
        remapped = migration.with(plan_mapping: {"other" => "catalog"})

        expect(described_class.filter(remapped, external_ids)).to eq(Set["unmapped"])
      end
    end

    context "when no plan of the organization is mapped" do
      let(:plan_mapping) { {"missing" => "catalog"} }

      before { migration }

      it "keeps nothing without querying the subscriptions" do
        statements = capture_sql { expect(described_class.filter(migration, external_ids)).to be_empty }

        expect(statements.grep(/subscriptions/)).to be_empty
      end
    end

    context "with no id" do
      it { expect(described_class.filter(migration, [])).to eq(Set[]) }
    end
  end

  describe ".expire!" do
    it "drops the snapshots" do
      described_class.filter(migration, external_ids)
      described_class.expire!

      statements = capture_sql { described_class.filter(migration, ["mapped"]) }

      expect(statements).not_to be_empty
    end
  end
end
