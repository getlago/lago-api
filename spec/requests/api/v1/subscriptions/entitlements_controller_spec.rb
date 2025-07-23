# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Subscriptions::EntitlementsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege1) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:privilege2) { create(:privilege, organization:, feature:, code: "root?", value_type: "boolean") }

  around { |test| lago_premium!(&test) }

  describe "GET /api/v1/subscriptions/:external_id/entitlements" do
    subject { get_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements" }

    let(:entitlement) { create(:entitlement, plan:, feature:) }
    let(:entitlement_value1) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 30) }
    let(:sub_entitlement) { create(:entitlement, subscription_id: subscription.id, plan: nil, feature:) }
    let(:entitlement_value2) { create(:entitlement_value, entitlement: sub_entitlement, privilege: privilege2, value: true) }

    before do
      entitlement_value1
      entitlement_value2
    end

    it_behaves_like "a Premium API endpoint"

    it "returns a list of entitlements" do
      subject

      expect(response).to have_http_status(:success)
      se = json[:entitlements].sole
      expect(se).to include({
        code: "seats",
        name: "Feature Name",
        description: "Feature Description",
        overrides: {root?: true}
      })
      expect(se[:privileges]).to contain_exactly({
        code: "root?",
        name: nil,
        value_type: "boolean",
        config: {},
        value: true,
        plan_value: nil,
        override_value: true
      }, {
        code: "max",
        name: nil,
        value_type: "integer",
        config: {},
        value: 30,
        plan_value: 30,
        override_value: nil
      })
    end

    it "returns not found error when subscription does not exist" do
      get_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements"

      expect(response).to be_not_found_error("subscription")
    end
  end

  describe "PATCH /api/v1/subscriptions/:external_id/entitlements" do
    subject { patch_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements", params }

    let(:entitlement) { create(:entitlement, plan: subscription.plan, feature:) }
    let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: "10", organization:) }
    let(:params) do
      {
        "entitlements" => {
          "seats" => {
            "max" => 60
          }
        }
      }
    end

    before do
      feature
      privilege1
      entitlement
      entitlement_value
    end

    it_behaves_like "a Premium API endpoint"

    it "updates existing entitlement value" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:entitlements]).to be_present
      expect(json[:entitlements].length).to eq(1)
      expect(json[:entitlements].first[:privileges].find { it[:code] == "max" }).to include({
        value: 60,
        plan_value: 10,
        override_value: 60
      })
      expect(json[:entitlements].first[:overrides]).to eq({
        max: 60
      })
    end

    it "does not create new entitlement" do
      expect {
        subject
      }.to change(Entitlement::Entitlement, :count).from(1).to(2)
    end

    context "when privilege value does not exist" do
      let(:privilege2) { create(:privilege, organization:, feature:, code: "max_admins", value_type: "integer") }
      let(:params) do
        {
          "entitlements" => {
            "seats" => {
              "max_admins" => 30
            }
          }
        }
      end

      before do
        privilege2
      end

      it "creates new entitlement value" do
        expect {
          subject
        }.to change(Entitlement::EntitlementValue, :count).by(1)
      end

      it "creates entitlement value with correct value" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:entitlements].first[:privileges].find { it[:code] == "max_admins" }[:value]).to eq(30)
      end
    end

    context "when entitlement does not exist" do
      let(:new_feature) { create(:feature, organization:, code: "storage") }
      let(:new_privilege) { create(:privilege, organization:, feature: new_feature, code: "max_gb", value_type: "integer") }
      let(:params) do
        {
          "entitlements" => {
            "storage" => {
              "max_gb" => 100
            }
          }
        }
      end

      before do
        new_feature
        new_privilege
      end

      it "creates new entitlement" do
        expect {
          subject
        }.to change(Entitlement::Entitlement, :count).by(1)
      end

      it "creates new entitlement value" do
        expect {
          subject
        }.to change(Entitlement::EntitlementValue, :count).by(1)
      end
    end

    context "when feature does not exist" do
      let(:params) do
        {
          "entitlements" => {
            "nonexistent_feature" => {
              "max" => 60
            }
          }
        }
      end

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("feature")
      end
    end

    context "when privilege does not exist" do
      let(:params) do
        {
          "entitlements" => {
            "seats" => {
              "nonexistent_privilege" => 60
            }
          }
        }
      end

      it "returns not found error" do
        subject

        expect(response).to be_not_found_error("privilege")
      end
    end

    context "when subscription does not exist" do
      it "returns not found error" do
        patch_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements", params

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "when entitlements params is empty" do
      let(:params) do
        {
          "entitlements" => {}
        }
      end

      it "returns success with existing entitlements" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:entitlements]).to be_present
        expect(json[:entitlements].first[:privileges].find { it[:code] == "max" }[:value]).to eq(10)
      end
    end
  end

  describe "DELETE /api/v1/subscriptions/external_id/entitlements/:feature_code" do
    subject { delete_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{feature.code}" }

    let(:entitlement) { create(:entitlement, subscription_id: subscription.id, plan: nil, feature:) }
    let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 30, organization:) }

    before do
      entitlement
      entitlement_value
    end

    it_behaves_like "a Premium API endpoint"

    it "deletes the entitlement and its values" do
      expect { subject }.to change(feature.entitlements, :count).by(-1)
        .and change(feature.entitlement_values, :count).by(-1)

      expect(response).to have_http_status(:success)
    end

    it "returns not found error when subscription does not exist" do
      delete_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements/#{feature.code}"

      expect(response).to be_not_found_error("subscription")
    end

    it "returns not found error when entitlement does not exist" do
      delete_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/invalid_feature"

      expect(response).to be_not_found_error("entitlement")
    end
  end

  describe "POST /api/v1/subscriptions/external_id/entitlements/:feature_code/remove" do
    subject { post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{feature.code}/remove" }

    let(:entitlement) { create(:entitlement, plan:, feature:) }

    before do
      entitlement
    end

    it_behaves_like "a Premium API endpoint"

    it "creates a subscription feature removal" do
      expect { subject }.to change(Entitlement::SubscriptionFeatureRemoval, :count).by(1)

      expect(response).to have_http_status(:success)
    end

    it "returns not found error when subscription does not exist" do
      post_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements/#{feature.code}/remove"

      expect(response).to be_not_found_error("subscription")
    end

    it "returns not found error when feature does not exist" do
      post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/invalid_feature/remove"

      expect(response).to be_not_found_error("feature")
    end

    context "when feature is not available in the plan" do
      let(:other_feature) { create(:feature, organization:, code: "other_feature") }

      it "returns validation error" do
        post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{other_feature.code}/remove"

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:feature]).to eq ["feature_not_available_in_plan"]
      end
    end

    context "when removal already exists" do
      let(:existing_removal) { create(:subscription_feature_removal, organization:, feature:, subscription_id: subscription.id) }

      it "returns validation error" do
        existing_removal
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:code]).to eq("validation_errors")
        expect(json[:error_details][:feature]).to eq ["feature_already_removed"]
      end
    end
  end

  describe "POST /api/v1/subscriptions/external_id/entitlements/:feature_code/restore" do
    subject { post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{feature.code}/restore" }

    let(:subscription_feature_removal) { create(:subscription_feature_removal, organization:, feature:, subscription_id: subscription.id) }

    before do
      subscription_feature_removal
    end

    it_behaves_like "a Premium API endpoint"

    it "discards the subscription feature removal" do
      expect { subject }.to change { subscription_feature_removal.reload.discarded? }.from(false).to(true)

      expect(response).to have_http_status(:success)
    end

    it "returns not found error when subscription does not exist" do
      post_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements/#{feature.code}/restore"

      expect(response).to be_not_found_error("subscription")
    end

    it "returns not found error when feature does not exist" do
      post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/invalid_feature/restore"

      expect(response).to be_not_found_error("feature")
    end

    context "when removal does not exist" do
      let(:other_feature) { create(:feature, organization:, code: "other_feature") }

      it "returns not found error" do
        post_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{other_feature.code}/restore"

        expect(response).to be_not_found_error("subscription_feature_removal")
      end
    end
  end
end
