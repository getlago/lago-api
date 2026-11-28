# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Entitlement do
  subject { build(:entitlement) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature")
      expect(subject).to belong_to(:plan).optional
      expect(subject).to belong_to(:catalog_plan).optional
      expect(subject).to belong_to(:subscription).optional
      expect(subject).to belong_to(:contract).optional
      expect(subject).to have_many(:values).class_name("Entitlement::EntitlementValue").inverse_of(:entitlement).dependent(:destroy)
    end
  end

  describe "Scopes" do
    describe ".newest_first" do
      let(:organization) { create(:organization) }
      let(:created_at) { Time.zone.parse("2026-09-04T10:00:00Z") }
      let(:recent) { create(:entitlement, organization:, created_at: created_at + 1.day) }
      let(:same_time_higher_id) { create(:entitlement, organization:, id: "00000000-0000-0000-0000-000000000002", created_at:) }
      let(:same_time_lower_id) { create(:entitlement, organization:, id: "00000000-0000-0000-0000-000000000001", created_at:) }

      before do
        recent
        same_time_higher_id
        same_time_lower_id
      end

      it "orders by creation, newest first, then by id" do
        expect(described_class.where(organization:).newest_first).to eq([recent, same_time_lower_id, same_time_higher_id])
      end
    end
  end

  describe "#owner_plan" do
    it "returns the catalog plan of a catalog plan entitlement" do
      catalog_plan = build_stubbed(:catalog_plan)
      expect(build_stubbed(:entitlement, plan: nil, catalog_plan:).owner_plan).to eq(catalog_plan)
    end

    it "returns the plan of a legacy plan entitlement" do
      plan = build_stubbed(:plan)
      expect(build_stubbed(:entitlement, plan:).owner_plan).to eq(plan)
    end

    it "returns nil for a subscription entitlement" do
      expect(build_stubbed(:entitlement, plan: nil, subscription: build_stubbed(:subscription)).owner_plan).to be_nil
    end
  end

  describe "validations" do
    describe "exactly_one_parent_present validation" do
      let_it_be(:organization) { create_default(:organization) }
      let_it_be(:plan) { create_default(:plan, organization:) }
      let_it_be(:customer) { create_default(:customer) }

      let(:feature) { create(:feature, organization:) }
      let(:subscription) { create(:subscription, organization:) }

      it "is valid when only plan_id is present" do
        entitlement = build(:entitlement, organization:, feature:, plan:, subscription: nil)
        expect(entitlement).to be_valid
      end

      it "is valid when only subscription is present" do
        entitlement = build(:entitlement, organization:, feature:, plan: nil, subscription:)
        expect(entitlement).to be_valid
      end

      it "is valid when only catalog_plan is present" do
        catalog_plan = create(:catalog_plan, organization:)
        entitlement = build(:entitlement, organization:, feature:, plan: nil, catalog_plan:)
        expect(entitlement).to be_valid
      end

      it "is valid when only contract is present" do
        entitlement = build(:entitlement, :contract, organization:, feature:)
        expect(entitlement).to be_valid
      end

      it "counts an unsaved parent through the association" do
        entitlement = build(:entitlement, organization:, feature:, plan: build(:plan, organization:), subscription: nil)
        expect(entitlement).to be_valid
      end

      it "is invalid when a plan and a catalog_plan are both present" do
        catalog_plan = create(:catalog_plan, organization:)
        entitlement = build(:entitlement, organization:, feature:, plan:, catalog_plan:)
        expect(entitlement).not_to be_valid
        expect(entitlement.errors[:base]).to eq(["one_of_plan_or_subscription_required"])
      end

      it "is invalid when a catalog_plan and a contract are both present" do
        entitlement = build(:entitlement, :contract, organization:, feature:, catalog_plan: create(:catalog_plan, organization:))
        expect(entitlement).not_to be_valid
        expect(entitlement.errors[:base]).to eq(["one_of_plan_or_subscription_required"])
      end

      it "is invalid when both plan_id and subscription are present" do
        entitlement = build(:entitlement, organization:, feature:, plan:, subscription:)
        expect(entitlement).not_to be_valid
        expect(entitlement.errors[:base]).to eq(["one_of_plan_or_subscription_required"])
      end

      it "is invalid when neither plan_id nor subscription are present" do
        entitlement = build(:entitlement, organization:, feature:, plan: nil, subscription: nil)
        expect(entitlement).not_to be_valid
        expect(entitlement.errors[:base]).to eq(["one_of_plan_or_subscription_required"])
      end
    end

    describe "database parent guard" do
      let(:organization) { create(:organization) }
      let(:feature) { create(:feature, organization:) }

      it "rejects a row with no parent even past model validation" do
        entitlement = build(:entitlement, organization:, feature:, plan: nil, subscription: nil)

        expect { entitlement.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it "rejects a row with two parents even past model validation" do
        entitlement = build(
          :entitlement,
          organization:,
          feature:,
          plan: create(:plan, organization:),
          subscription: create(:subscription, organization:)
        )

        expect { entitlement.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it "saves a row owned by a contract only" do
        entitlement = build(:entitlement, :contract, organization:, feature:)

        expect(entitlement.save(validate: false)).to be(true)
        expect(entitlement.reload.contract_id).to eq(entitlement.contract.id)
      end

      it "rejects a row with a catalog plan and a contract even past model validation" do
        entitlement = build(
          :entitlement,
          :contract,
          organization:,
          feature:,
          catalog_plan: create(:catalog_plan, organization:)
        )

        expect { entitlement.save(validate: false) }
          .to raise_error(ActiveRecord::StatementInvalid, /entitlement_check_exactly_one_parent/)
      end

      it "rejects a second live row for a contract and a feature" do
        entitlement = create(:entitlement, :contract, organization:, feature:)
        duplicate = build(:entitlement, :contract, organization:, feature:, contract: entitlement.contract)

        expect { duplicate.save(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique, /idx_unique_feature_per_contract/)
      end

      it "saves a row for a contract and a feature once the previous one is discarded" do
        entitlement = create(:entitlement, :contract, organization:, feature:)
        entitlement.discard!
        replacement = build(:entitlement, :contract, organization:, feature:, contract: entitlement.contract)

        expect(replacement.save(validate: false)).to be(true)
      end
    end
  end
end
