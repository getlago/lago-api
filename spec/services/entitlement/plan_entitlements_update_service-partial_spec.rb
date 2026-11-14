# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementsUpdateService do
  subject(:result) { described_class.call(organization:, plan:, entitlements_params:, partial: true) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
  let(:privilege2) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }
  let(:entitlement) { create(:entitlement, plan:, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, organization:, value: 10) }
  let(:entitlements_params) do
    {
      feature.code => {
        privilege.code => 60
      }
    }
  end

  before do
    privilege
    privilege2
    entitlement
    entitlement_value
  end

  describe "#call", :premium do
    it "returns success" do
      expect(result).to be_success
    end

    it "updates existing entitlement value" do
      expect { result }.to change { entitlement_value.reload.value }.from("10").to("60")
    end

    it "does not create new entitlement" do
      expect { result }.not_to change(Entitlement::Entitlement, :count)
    end

    it "does not create new entitlement value" do
      expect { result }.not_to change(Entitlement::EntitlementValue, :count)
    end

    it "returns entitlements in the result" do
      expect(result.entitlements).to include(entitlement)
    end

    it "sends `plan.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
    end

    context "when privilege value does not exist" do
      let(:entitlements_params) do
        {
          feature.code => {
            privilege2.code => 30
          }
        }
      end

      it "creates new entitlement value" do
        expect { result }.to change(Entitlement::EntitlementValue, :count).by(1)
      end

      it "creates entitlement value with correct attributes" do
        ent_value = result.entitlements.find { it.entitlement_feature_id == feature.id }
          .values.find { it.entitlement_privilege_id == privilege2.id }

        expect(ent_value.value).to eq("30")
      end
    end

    context "when entitlement does not exist" do
      let(:new_feature) { create(:feature, organization:) }
      let(:new_privilege) { create(:privilege, organization:, feature: new_feature, code: "max_users", value_type: "integer") }
      let(:entitlements_params) do
        {
          new_feature.code => {
            new_privilege.code => 50
          }
        }
      end

      it "creates new entitlement" do
        expect { result }.to change(Entitlement::Entitlement, :count).by(1)
      end

      it "creates new entitlement value" do
        expect { result }.to change(Entitlement::EntitlementValue, :count).by(1)
      end

      it "creates entitlement with correct attributes" do
        ent_value = result.entitlements.find { it.entitlement_feature_id == new_feature.id }
          .values.find { it.entitlement_privilege_id == new_privilege.id }

        expect(ent_value.value).to eq("50")
        expect(ent_value.organization).to eq(organization)
        expect(ent_value.entitlement.plan).to eq(plan)
        expect(ent_value.entitlement.feature).to eq(new_feature)
        expect(ent_value.entitlement.organization).to eq(organization)
      end
    end

    context "when updating multiple features" do
      let(:feature2) { create(:feature, organization:) }
      let(:privilege3) { create(:privilege, organization:, feature: feature2, code: "max_storage", value_type: "integer") }
      let(:entitlement2) { create(:entitlement, organization:, plan:, feature: feature2) }
      let(:entitlement_value2) { create(:entitlement_value, entitlement: entitlement2, privilege: privilege3, organization:, value: "100") }
      let(:entitlements_params) do
        {
          feature.code => {
            privilege.code => 60
          },
          feature2.code => {
            privilege3.code => 200
          }
        }
      end

      before do
        entitlement2
        entitlement_value2
      end

      it "updates both entitlement values" do
        result
        expect(entitlement_value.reload.value).to eq("60")
        expect(entitlement_value2.reload.value).to eq("200")
      end

      it "returns both entitlements in the result" do
        expect(result.entitlements).to include(entitlement, entitlement2)
      end

      context "when the existing value of the second feature is set to null" do
        let(:entitlements_params) do
          {
            feature.code => {privilege.code => 60},
            feature2.code => {privilege3.code => nil}
          }
        end

        it "records the second feature and its privilege as the failing entry and writes nothing" do
          expect { result }.not_to change { entitlement_value.reload.value }

          expect(result.error.messages).to eq({"privilege.value": ["value_is_mandatory"]})
          expect(result.failed_field).to eq(:"entitlements.#{feature2.code}.max_storage")
        end
      end
    end

    context "when plan is nil" do
      let(:result) { described_class.call(organization:, plan: nil, entitlements_params:, partial: true) }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "when plan is discarded" do
      let(:plan) { create(:plan, organization:, deleted_at: Time.current) }

      it "returns not found failure and writes nothing" do
        expect { result }.not_to change { entitlement_value.reload.value }

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
        expect(SendWebhookJob).not_to have_been_enqueued
        expect(Utils::ActivityLog).not_to have_produced("plan.updated")
      end
    end

    context "when a concurrent request creates the same entitlement" do
      let(:new_feature) { create(:feature, organization:, code: "storage") }
      let(:new_privilege) { create(:privilege, organization:, feature: new_feature, code: "max_gb", value_type: "integer") }
      let(:entitlements_params) { {new_feature.code => {new_privilege.code => 100}} }

      before do
        # The concurrent request inserts its row after this one read the plan entitlements.
        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken feature" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(feature: ["value_already_exist"])
        expect(result.failed_field).to be_nil
        expect(SendWebhookJob).not_to have_been_enqueued
        expect(Utils::ActivityLog).not_to have_produced("plan.updated")
      end
    end

    context "when a concurrent request creates the same entitlement value" do
      let(:entitlements_params) { {feature.code => {privilege2.code => 5}} }

      before do
        allow(Entitlement::EntitlementValue).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken privilege" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(privilege: ["value_already_exist"])
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "with a catalog plan" do
      let(:plan) { create(:catalog_plan, organization:) }
      let(:entitlement) { create(:entitlement, :catalog_plan, catalog_plan: plan, feature:) }
      let(:new_feature) { create(:feature, organization:, code: "storage") }
      let(:new_privilege) { create(:privilege, organization:, feature: new_feature, code: "max_gb", value_type: "integer") }
      let(:entitlements_params) { {new_feature.code => {new_privilege.code => "100"}} }

      it "adds the feature and keeps the other ones" do
        expect(result).to be_success

        new_entitlement = plan.entitlements.find_by!(feature: new_feature)
        expect(new_entitlement.catalog_plan_id).to eq(plan.id)
        expect(new_entitlement.plan_id).to be_nil
        expect(new_entitlement.values.sole.value).to eq("100")
        expect(entitlement_value.reload.value).to eq("10")
        expect(result.entitlements).to eq([entitlement, new_entitlement])
      end

      it "sends one `plan.entitlements_updated` webhook after commit and no `plan.updated` one" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.entitlements_updated", plan).exactly(:once)
        expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", plan)
      end

      context "when a concurrent request creates the same entitlement" do
        before do
          # The concurrent request inserts its row after this one read the plan entitlements.
          allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, **attributes|
            original.call(**attributes)
            original.call(**attributes)
          end
        end

        it "returns the validation error of a taken feature" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(feature: ["value_already_exist"])
          expect(Utils::ActivityLog).not_to have_produced("plan.updated")
        end
      end

      context "when a concurrent request creates the same entitlement value" do
        let(:entitlements_params) { {feature.code => {privilege2.code => 5}} }

        before do
          allow(Entitlement::EntitlementValue).to receive(:create!).and_wrap_original do |original, **attributes|
            original.call(**attributes)
            original.call(**attributes)
          end
        end

        it "returns the validation error of a taken privilege" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(privilege: ["value_already_exist"])
          expect(entitlement.values.where(privilege: privilege2)).to be_empty
          expect(Utils::ActivityLog).not_to have_produced("plan.updated")
        end
      end
    end

    context "when another unique index refuses the write" do
      let(:new_feature) { create(:feature, organization:, code: "storage") }
      let(:entitlements_params) { {new_feature.code => {}} }

      before do
        allow(Entitlement::Entitlement).to receive(:create!) do
          create(:plan, organization:).update_column(:code, plan.code) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it "raises the error" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique, /index_plans_on_organization_id_and_code/)
      end
    end

    context "when updating many features" do
      def feature_queries(count)
        features = create_list(:feature, count, organization:)
        privileges = features.map { create(:privilege, organization:, feature: it, code: "max", value_type: "integer") }
        params = features.zip(privileges).to_h { |f, p| [f.code, {p.code => 1}] }

        queries = 0
        counter = ->(*, payload) { queries += 1 if payload[:sql].include?(%("entitlement_features")) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          described_class.call(organization:, plan:, entitlements_params: params, partial: true)
        end
        queries
      end

      it "loads the features a fixed number of times" do
        expect(feature_queries(100)).to eq(feature_queries(2))
      end
    end

    context "when feature does not exist" do
      let(:entitlements_params) do
        {
          "nonexistent_feature" => {
            privilege.code => 60
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
      end
    end

    context "when privilege does not exist" do
      let(:entitlements_params) do
        {
          feature.code => {
            "nonexistent_privilege" => 60
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end

    context "when value is invalid for select privilege" do
      let(:select_privilege) { create(:privilege, organization:, feature:, code: "provider", value_type: "select", config: {"select_options" => ["okta", "ad"]}) }
      let(:entitlements_params) do
        {
          feature.code => {
            select_privilege.code => "invalid_option"
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:provider_privilege_value]).to eq ["value_not_in_select_options"]
      end
    end

    context "when entitlements_params is empty" do
      let(:entitlements_params) { {} }

      it "returns success" do
        expect(result).to be_success
      end

      it "does not change any entitlement values" do
        expect { result }.not_to change { entitlement_value.reload.value }
      end
    end

    context "with bullet gem to detect N+1 queries", bullet: {unused_eager_loading: false} do
      context "when updating multiple features with multiple privileges" do
        let(:feature) { create(:feature, organization:) }
        let(:feature2) { create(:feature, organization:, code: "storage") }
        let(:feature3) { create(:feature, organization:, code: "api") }
        let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
        let(:privilege2) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }
        let(:privilege3) { create(:privilege, organization:, feature: feature2, code: "max_storage", value_type: "integer") }
        let(:privilege4) { create(:privilege, organization:, feature: feature2, code: "max_bandwidth", value_type: "integer") }
        let(:privilege5) { create(:privilege, organization:, feature: feature3, code: "max_requests", value_type: "integer") }
        let(:privilege6) { create(:privilege, organization:, feature: feature3, code: "max_rate_limit", value_type: "integer") }
        let(:entitlement2) { create(:entitlement, organization:, plan:, feature: feature2) }
        let(:entitlement3) { create(:entitlement, organization:, plan:, feature: feature3) }
        let(:entitlement_value2) { create(:entitlement_value, entitlement: entitlement2, privilege: privilege3, organization:, value: "100") }
        let(:entitlement_value3) { create(:entitlement_value, entitlement: entitlement3, privilege: privilege5, organization:, value: "1000") }
        let(:entitlements_params) do
          {
            feature.code => {
              privilege.code => 60,
              privilege2.code => 5
            },
            feature2.code => {
              privilege3.code => 200,
              privilege4.code => 50
            },
            feature3.code => {
              privilege5.code => 2000,
              privilege6.code => 100
            }
          }
        end

        before do
          feature2
          feature3
          privilege3
          privilege4
          privilege5
          privilege6
          entitlement2
          entitlement3
          entitlement_value2
          entitlement_value3

          # NOTE: SendWebhookJob.perform_later checks organization.webhook_endpoints,
          #       which Bullet flags as an N+1. It is not part of this test.
          Bullet.add_safelist(type: :n_plus_one_query, class_name: "Organization", association: :webhook_endpoints)
        end

        after do
          Bullet.delete_safelist(type: :n_plus_one_query, class_name: "Organization", association: :webhook_endpoints)
        end

        it "does not trigger N+1 queries when updating multiple features and privileges" do
          result

          expect(result).to be_success
          expect(result.entitlements.count).to eq(3)
        end
      end
    end
  end
end
