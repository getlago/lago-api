# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Feature::SubscriptionsCountQuery do
  subject { described_class.new(organization:, filters: {feature_ids:}) }

  before do |example|
    example.example_group.before do
      Scenic.database.refresh_materialized_view(
        :entitlement_features_subscriptions_count,
        concurrently: false
      )
    end
  end

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }

    let(:feature) { create(:feature, organization:) }
    let(:feature_ids) { [feature.id] }

    context "with no subscriptions at all" do
      it "returns empty hash" do
        result = subject.call

        expect(result).to eq({})
      end
    end

    context "with a plan with no subscriptions" do
      before do
        create(:entitlement, feature:, plan:)
      end

      it "returns empty hash" do
        result = subject.call

        expect(result).to eq({})
      end
    end

    context "with only plan subscriptions" do
      before do
        create(:subscription, plan:)
        create(:subscription, :pending, plan:)
        create(:subscription, :terminated, plan:)
        create(:subscription, :canceled, plan:)

        create(:entitlement, feature:, plan:)
      end

      it "returns the number of active & pending plan subscriptions" do
        result = subject.call

        expect(result).to eq({feature.id => 2})
      end
    end

    context "with multiple plans" do
      let(:plan1) { create(:plan, organization:) }
      let(:plan2) { create(:plan, organization:) }

      before do
        create(:subscription, plan: plan1)
        create(:subscription, plan: plan2)
        create(:subscription, :pending, plan: plan2)

        create(:entitlement, feature:, plan: plan1)
        create(:entitlement, feature:, plan: plan2)
      end

      it "returns the number of all plans subscriptions" do
        result = subject.call

        expect(result).to eq({feature.id => 3})
      end
    end

    context "with plan overrides" do
      let(:plan1) { create(:plan, organization:) }
      let(:plan2) { create(:plan, organization:, parent: plan1) }

      before do
        create(:subscription, plan: plan1)
        create(:subscription, plan: plan2)

        create(:entitlement, feature:, plan: plan1)
      end

      it "includes overriden plan subscriptions to its parent plan" do
        result = subject.call

        expect(result).to eq({feature.id => 2})
      end
    end

    context "with a deleted plan" do
      let(:plan1) { create(:plan, organization:) }
      let(:plan2) { create(:plan, organization:, deleted_at: Time.zone.now) }

      before do
        create(:subscription, plan: plan1)
        create(:subscription, plan: plan2)

        create(:entitlement, feature:, plan: plan1)
        create(:entitlement, feature:, plan: plan2)
      end

      it "does not include deleted plan subscriptions" do
        result = subject.call

        expect(result).to eq({feature.id => 1})
      end
    end

    context "with only direct subscriptions" do
      let(:subscription1) { create(:subscription, plan:) }
      let(:subscription2) { create(:subscription, :pending, plan:) }
      let(:subscription3) { create(:subscription, :terminated, plan:) }
      let(:subscription4) { create(:subscription, :canceled, plan:) }

      before do
        create(:entitlement, :subscription, feature:, subscription: subscription1)
        create(:entitlement, :subscription, feature:, subscription: subscription2)
        create(:entitlement, :subscription, feature:, subscription: subscription3)
        create(:entitlement, :subscription, feature:, subscription: subscription4)
      end

      it "returns the number of active & pending direct subscriptions" do
        result = subject.call

        expect(result).to eq({feature.id => 2})
      end
    end

    context "with both plan and direct subscriptions" do
      let(:subscription1) { create(:subscription, plan:) }
      let(:subscription2) { create(:subscription, plan:) }
      let(:subscription3) { create(:subscription, organization:) }

      before do
        create(:entitlement, feature:, plan:)
        create(:entitlement, :subscription, feature:, subscription: subscription2)
        create(:entitlement, :subscription, feature:, subscription: subscription3)
      end

      it "returns the total number of plan and direct subscriptions" do
        result = subject.call

        expect(result).to eq({feature.id => 2})
      end
    end

    context "with feature removals" do
      let(:subscription) { create(:subscription, plan:) }

      before do
        create(:subscription, plan:)
        create(:entitlement, feature:, plan:)

        create(:subscription_feature_removal, feature:, subscription:)
      end

      it "does not include subscriptions for which the feature is removed" do
        result = subject.call

        expect(result).to eq({feature.id => 1})
      end
    end

    context "with deleted plan entitlements" do
      before do
        create(:subscription, plan:)
        create(:entitlement, feature:, plan:, deleted_at: Time.zone.now)
      end

      it "does not include deleted entitlement plan subscriptions" do
        result = subject.call

        expect(result).to eq({})
      end
    end

    context "with deleted subscription entitlements" do
      let(:subscription) { create(:subscription, plan:) }

      before do
        create(:entitlement, :subscription, feature:, subscription:, deleted_at: Time.zone.now)
      end

      it "does not include deleted entitlement direct subscriptions" do
        result = subject.call

        expect(result).to eq({})
      end
    end

    context "with deleted feature removals" do
      let(:subscription) { create(:subscription, plan:) }

      before do
        create(:subscription_feature_removal, feature:, subscription:, deleted_at: Time.zone.now)
        create(:entitlement, feature:, plan:)
      end

      it "includes subscriptions with a deleted feature removal" do
        result = subject.call

        expect(result).to eq({feature.id => 1})
      end
    end

    context "with multiple features" do
      let(:subscription) { create(:subscription, organization:) }

      let(:feature1) { create(:feature, organization:) }
      let(:feature2) { create(:feature, organization:) }

      let(:feature_ids) { [feature1.id, feature2.id] }

      before do
        create(:subscription, plan:)
        create(:subscription, :pending, plan:)

        create(:entitlement, feature: feature1, plan:)
        create(:entitlement, :subscription, feature: feature2, subscription:)
      end

      it "returns subscriptions count for each feature" do
        result = subject.call

        expect(result).to eq({
          feature1.id => 2,
          feature2.id => 1
        })
      end
    end
  end
end
