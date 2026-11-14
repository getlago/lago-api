# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeatureRemoval do
  subject { build(:subscription_feature_removal) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription).optional
      expect(subject).to belong_to(:contract).optional
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature").optional
      expect(subject).to belong_to(:privilege).class_name("Entitlement::Privilege").optional
    end
  end

  describe "validations" do
    let(:organization) { create(:organization) }
    let(:feature) { create(:feature, organization:) }
    let(:subscription) { create(:subscription, organization:) }
    let(:contract) { create(:contract, organization:) }

    it "is valid when only subscription is present" do
      removal = build(:subscription_feature_removal, organization:, feature:, subscription:)
      expect(removal).to be_valid
    end

    it "is valid when only contract is present" do
      removal = build(:subscription_feature_removal, :contract, organization:, feature:, contract:)
      expect(removal).to be_valid
    end

    it "is invalid when subscription and contract are both present" do
      removal = build(:subscription_feature_removal, organization:, feature:, subscription:, contract:)
      expect(removal).not_to be_valid
      expect(removal.errors[:base]).to eq(["one_of_subscription_or_contract_required"])
    end

    it "is invalid when neither subscription nor contract is present" do
      removal = build(:subscription_feature_removal, organization:, feature:, subscription: nil)
      expect(removal).not_to be_valid
      expect(removal.errors[:base]).to eq(["one_of_subscription_or_contract_required"])
    end

    describe "database owner guard" do
      it "saves a row owned by a contract only" do
        removal = build(:subscription_feature_removal, :contract, organization:, feature:, contract:)

        expect(removal.save(validate: false)).to be(true)
        expect(removal.reload.contract_id).to eq(contract.id)
      end

      it "rejects a row with a subscription and a contract even past model validation" do
        removal = build(:subscription_feature_removal, organization:, feature:, subscription:, contract:)

        expect { removal.save(validate: false) }
          .to raise_error(ActiveRecord::StatementInvalid, /entitlement_removal_check_exactly_one_owner/)
      end

      it "rejects a row with no owner even past model validation" do
        removal = build(:subscription_feature_removal, organization:, feature:, subscription: nil)

        expect { removal.save(validate: false) }
          .to raise_error(ActiveRecord::StatementInvalid, /entitlement_removal_check_exactly_one_owner/)
      end
    end
  end
end
