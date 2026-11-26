# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementsUpdateService do
  subject(:result) { described_class.call(organization:, plan:, entitlements_params:, partial: false) }

  let_it_be(:organization, refind: true) { create(:organization) }
  let_it_be(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:entitlements_params) do
    {
      "seats" => {
        "max" => 25
      }
    }
  end

  before do
    feature
    privilege
  end

  describe "#call", :premium do
    it "returns success" do
      expect(result).to be_success
    end

    context "when a feature value is null" do
      let(:entitlements_params) { {"seats" => nil} }

      it "adds the entitlement with no values, as before" do
        expect(result).to be_success
        expect(plan.entitlements.count).to eq(1)
        expect(plan.entitlements.first.values).to be_empty
      end
    end

    it "creates entitlements for the plan" do
      expect { result }.to change { plan.entitlements.count }.by(1)
    end

    it "creates entitlement values" do
      expect { result }.to change(Entitlement::EntitlementValue, :count).by(1)
    end

    it "returns the entitlements in the result" do
      expect(result.entitlements).to be_present
      expect(result.entitlements.count).to eq(1)
    end

    it "sends `plan.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(plan)
    end

    context "when send_webhook is false" do
      subject(:result) { described_class.call(organization:, plan:, entitlements_params:, partial: false, send_webhook: false) }

      it "does not send the `plan.updated` webhook" do
        expect { subject }.not_to have_enqueued_job(SendWebhookJob).with("plan.updated", plan)
      end

      it "does not produce an activity log" do
        subject
        expect(Utils::ActivityLog).not_to have_received(:produce)
      end
    end

    it "creates the entitlement with correct values" do
      result
      entitlement = plan.entitlements.first
      entitlement_value = entitlement.values.first

      expect(entitlement.feature).to eq(feature)
      expect(entitlement_value.privilege).to eq(privilege)
      expect(entitlement_value.value).to eq("25")
    end

    context "when plan has existing entitlements" do
      let(:existing_entitlement) { create(:entitlement, organization:, plan:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      before do
        existing_entitlement
        existing_value
      end

      it "deletes existing entitlements and their values" do
        result
        expect(existing_value.reload.deleted_at).to be_present
        expect(existing_entitlement.reload.deleted_at).to be_present
      end

      it "creates new entitlements" do
        result
        new_entitlement = plan.entitlements.sole
        new_value = new_entitlement.values.sole

        expect(new_entitlement).not_to eq(existing_entitlement)
        expect(new_value.value).to eq("25")
      end
    end

    context "when entitlements_params is empty" do
      let(:entitlements_params) { {} }

      it "returns success" do
        expect(result).to be_success
      end

      it "does not create any entitlements" do
        expect { result }.not_to change { plan.entitlements.count }
      end
    end

    context "when feature has multiple privileges" do
      let(:privilege2) { create(:privilege, organization:, feature:, code: "max_admins", value_type: "integer") }
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => 25,
            "max_admins" => 5
          }
        }
      end

      before do
        privilege2
      end

      it "creates entitlement values for all privileges" do
        expect { result }.to change(Entitlement::EntitlementValue, :count).by(2)
      end

      it "creates correct values for each privilege" do
        result
        entitlement = plan.entitlements.first
        values = entitlement.values.index_by(&:privilege)

        expect(values[privilege].value).to eq("25")
        expect(values[privilege2].value).to eq("5")
      end
    end

    context "when feature does not exist" do
      let(:entitlements_params) do
        {
          "nonexistent_feature" => {
            "max" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
        expect(result.failed_field).to eq(:"entitlements.nonexistent_feature")
      end
    end

    context "when privilege does not exist" do
      let(:entitlements_params) do
        {
          "seats" => {
            "nonexistent_privilege" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
        expect(result.failed_field).to eq(:"entitlements.seats.nonexistent_privilege")
      end
    end

    context "when the privileges of a feature are not a map" do
      let(:entitlements_params) { {"seats" => [50]} }

      it "returns a validation failure on the feature entry and stores nothing" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq("entitlements.seats": ["value_is_invalid"])
        expect(result.failed_field).to be_nil
        expect(plan.entitlements).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when the privileges of a feature are blank" do
      let(:entitlements_params) { {"seats" => nil} }

      it "reads them as no values on a legacy plan" do
        expect(result).to be_success
        expect(plan.entitlements.sole.values).to be_empty
      end

      context "with a catalog plan" do
        subject(:result) { described_class.call(organization:, plan: catalog_plan, entitlements_params:, partial: false) }

        let(:catalog_plan) { create(:catalog_plan, organization:) }

        it "returns a validation failure on the feature entry and stores nothing" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq("entitlements.seats": ["value_is_invalid"])
          expect(catalog_plan.entitlements).to be_empty
        end
      end
    end

    context "when plan is nil" do
      subject(:result) { described_class.call(organization:, plan: nil, entitlements_params:, partial: false) }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("plan_not_found")
        expect(result.failed_field).to be_nil
      end
    end

    context "when feature has no privileges in payload" do
      let(:entitlements_params) do
        {
          "seats" => {}
        }
      end

      it "creates entitlement without values" do
        expect { result }.to change { plan.entitlements.count }.by(1).and(not_change(Entitlement::EntitlementValue, :count))
      end
    end

    context "when value is boolean" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
      let(:entitlements_params) do
        {
          "seats" => {
            "enabled" => true
          }
        }
      end

      it "converts boolean to string" do
        result
        entitlement_value = plan.entitlements.first.values.first
        expect(entitlement_value.value).to eq("t")
      end
    end

    context "when value is string" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "provider", value_type: "string") }
      let(:entitlements_params) do
        {
          "seats" => {
            "provider" => "okta"
          }
        }
      end

      it "converts string to string" do
        result
        entitlement_value = plan.entitlements.first.values.first
        expect(entitlement_value.value).to eq("okta")
      end
    end

    context "when privilege value is invalid" do
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => [12, 13]
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages).to eq({max_privilege_value: ["value_is_invalid"]})
        expect(result.error.codes).to eq({"entitlements.seats.max": ["value_is_invalid"]})
        expect(result.error.meta).to eq({})
        expect(result.failed_field).to be_nil
      end
    end

    context "when two features share a privilege code and the second value is invalid" do
      let(:other_feature) { create(:feature, organization:, code: "storage") }
      let(:other_privilege) { create(:privilege, organization:, feature: other_feature, code: "max", value_type: "integer") }
      let(:entitlements_params) do
        {
          "seats" => {"max" => 25},
          "storage" => {"max" => "lots"}
        }
      end

      before { other_privilege }

      it "records the second feature and its privilege as the failing entry and writes nothing" do
        expect { result }.not_to change(Entitlement::Entitlement, :count)
        expect(result).not_to be_success
        expect(result.error.messages).to eq({max_privilege_value: ["value_is_invalid"]})
        expect(result.error.codes).to eq({"entitlements.storage.max": ["value_is_invalid"]})
        expect(result.failed_field).to be_nil
      end
    end

    context "when the failing feature has no privilege after a feature with privileges" do
      let(:other_feature) { create(:feature, organization:, code: "storage") }
      let(:entitlements_params) do
        {
          "seats" => {"max" => 25},
          "storage" => {"unknown" => 1}
        }
      end

      before { other_feature }

      it "records the privilege of the failing feature, not the one of the previous feature" do
        expect(result.error.error_code).to eq("privilege_not_found")
        expect(result.failed_field).to eq(:"entitlements.storage.unknown")
      end
    end

    context "when an unknown feature follows a feature with privileges" do
      let(:entitlements_params) do
        {
          "seats" => {"max" => 25},
          "unknown" => {"max" => 1}
        }
      end

      it "records no privilege code" do
        expect(result.error.error_code).to eq("feature_not_found")
        expect(result.failed_field).to eq(:"entitlements.unknown")
      end
    end

    context "when privilege value is nil" do
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => nil
          }
        }
      end

      it "returns a validation failure with privilege-prefixed errors" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({"privilege.value": ["value_is_mandatory"]})
        expect(result.error.codes).to eq({"entitlements.seats.max": ["value_is_mandatory"]})
        expect(result.failed_field).to be_nil
      end
    end

    context "when privilege value is not in select_options" do
      let(:privilege) { create(:privilege, organization:, feature:, code: "invitation", value_type: "select", config: {select_options: ["email", "phone", "slack"]}) }
      let(:entitlements_params) do
        {
          "seats" => {
            "invitation" => "okta"
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages).to eq({invitation_privilege_value: ["value_not_in_select_options"]})
        expect(result.error.codes).to eq({"entitlements.seats.invitation": ["value_not_in_select_options"]})
        expect(result.error.meta).to eq({"entitlements.seats.invitation": {allowed_values: ["email", "phone", "slack"]}})
        expect(result.failed_field).to be_nil
      end
    end

    context "with a catalog plan" do
      let(:plan) { create(:catalog_plan, organization:) }
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:old_feature) { create(:feature, organization:, code: "sso") }
      let(:old_privilege) { create(:privilege, organization:, feature: old_feature, code: "provider", value_type: "string") }
      let(:old_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature: old_feature) }
      let(:old_value) { create(:entitlement_value, organization:, entitlement: old_entitlement, privilege: old_privilege, value: "okta") }
      let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: other_plan, feature: old_feature) }
      let(:other_value) { create(:entitlement_value, organization:, entitlement: other_entitlement, privilege: old_privilege, value: "okta") }
      let(:string_privilege) { create(:privilege, organization:, feature:, code: "provider", value_type: "string") }
      let(:boolean_privilege) { create(:privilege, organization:, feature:, code: "enabled", value_type: "boolean") }
      let(:select_privilege) do
        create(:privilege, organization:, feature:, code: "invitation", value_type: "select", config: {select_options: %w[email phone]})
      end
      let(:entitlements_params) do
        {"seats" => {"max" => "25", "provider" => "okta", "enabled" => true, "invitation" => "phone"}}
      end

      before do
        # The per-entitlement events of a catalog plan are behind the entitlement_events flag.
        organization.enable_feature_flag!(:entitlement_events)
        string_privilege
        boolean_privilege
        select_privilege
        old_value
        other_value
      end

      context "without the entitlement_events flag" do
        before { organization.disable_feature_flag!(:entitlement_events) }

        it "logs nothing, sends no webhook and renders no entitlement" do
          allow(::V2::PlanEntitlementSerializer).to receive(:new).and_call_original

          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(Utils::ActivityLog).not_to have_received(:produce)
          expect(::V2::PlanEntitlementSerializer).not_to have_received(:new)
        end
      end

      context "when activity logs cannot be sent" do
        before { allow(Utils::ActivityLog).to receive(:available?).and_return(false) }

        it "logs nothing and still sends the webhooks" do
          expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).twice

          expect(Utils::ActivityLog).not_to have_received(:produce)
        end

        context "when the organization has no webhook endpoint" do
          before { organization.webhook_endpoints.destroy_all }

          it "renders no entitlement" do
            allow(::V2::PlanEntitlementSerializer).to receive(:new).and_call_original

            expect { result }.not_to have_enqueued_job(SendWebhookJob)

            expect(::V2::PlanEntitlementSerializer).not_to have_received(:new)
          end
        end
      end

      context "with a kept entitlement whose values change" do
        let(:entitlements_params) { {"sso" => {"provider" => "google"}} }

        before { old_entitlement.update_columns(updated_at: 1.day.ago) } # rubocop:disable Rails/SkipsModelValidations

        it "touches it, with or without the entitlement_events flag" do
          organization.disable_feature_flag!(:entitlement_events)

          freeze_time do
            result
            expect(old_entitlement.reload.updated_at).to eq(Time.current)
          end
        end
      end

      it "replaces the entitlements of the catalog plan" do
        expect(result).to be_success

        entitlement = plan.entitlements.sole
        expect(entitlement.feature).to eq(feature)
        expect(entitlement.catalog_plan_id).to eq(plan.id)
        expect(entitlement.plan_id).to be_nil
        expect(entitlement.values.to_h { [it.privilege.code, it.value] })
          .to eq("max" => "25", "provider" => "okta", "enabled" => "t", "invitation" => "phone")
        expect(old_entitlement.reload).to be_discarded
        expect(old_value.reload).to be_discarded
        expect(result.entitlements).to eq([entitlement])
      end

      it "leaves the entitlements of another catalog plan untouched" do
        result

        expect(other_entitlement.reload).not_to be_discarded
        expect(other_value.reload).not_to be_discarded
        expect(other_plan.entitlements.sole.values.sole.value).to eq("okta")
      end

      it "sends no plan.updated webhook or activity log" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob).with("plan.updated", plan)
        expect(Utils::ActivityLog).not_to have_produced("plan.updated")
      end

      it "logs the added and the dropped entitlement" do
        result

        # Newest privilege first: max is created before the three others.
        added_values = [
          {privilege_code: "invitation", value: "phone"},
          {privilege_code: "enabled", value: true},
          {privilege_code: "provider", value: "okta"},
          {privilege_code: "max", value: 25}
        ]
        added = plan.entitlements.sole
        expect(Utils::ActivityLog).to have_received(:produce).with(
          added, "plan_entitlement.created", after_commit: true,
          changes: {"values" => [nil, added_values]},
          activity_object: {
            lago_id: added.id,
            plan_code: plan.code,
            feature_code: "seats",
            values: added_values,
            created_at: added.created_at.iso8601,
            updated_at: added.updated_at.iso8601,
            deleted_at: nil
          }
        )
        dropped = Entitlement::Entitlement.with_discarded.find(old_entitlement.id)
        expect(Utils::ActivityLog).to have_received(:produce).with(
          old_entitlement, "plan_entitlement.deleted", after_commit: true,
          changes: {"values" => [[{privilege_code: "provider", value: "okta"}], nil]},
          activity_object: {
            lago_id: old_entitlement.id,
            plan_code: plan.code,
            feature_code: "sso",
            values: [{privilege_code: "provider", value: "okta"}],
            created_at: dropped.created_at.iso8601,
            updated_at: dropped.updated_at.iso8601,
            deleted_at: dropped.deleted_at.iso8601
          }
        )
        expect(dropped.deleted_at).to be_present
        expect(Utils::ActivityLog).to have_received(:produce).twice
      end

      context "with an added, a changed, a dropped and an unchanged entitlement" do
        let(:storage_feature) { create(:feature, organization:, code: "storage") }
        let(:storage_privilege) { create(:privilege, organization:, feature: storage_feature, code: "gb", value_type: "integer") }
        let(:api_feature) { create(:feature, organization:, code: "api") }
        let(:api_privilege) { create(:privilege, organization:, feature: api_feature, code: "calls", value_type: "integer") }
        let(:changed_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature:) }
        let(:unchanged_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature: api_feature) }
        let(:entitlements_params) do
          {"seats" => {"max" => 25}, "storage" => {"gb" => 100}, "api" => {"calls" => 1000}}
        end

        before do
          create(:entitlement_value, organization:, entitlement: changed_entitlement, privilege:, value: "10")
          create(:entitlement_value, organization:, entitlement: unchanged_entitlement, privilege: api_privilege, value: "1000")
          storage_privilege
        end

        it "writes one activity log of the matching type for each changed entitlement" do
          result

          added_entitlement = plan.entitlements.find_by!(feature: storage_feature)
          expect(Utils::ActivityLog).to have_received(:produce).with(
            added_entitlement, "plan_entitlement.created", after_commit: true,
            changes: {"values" => [nil, [{privilege_code: "gb", value: 100}]]},
            activity_object: hash_including(lago_id: added_entitlement.id, values: [{privilege_code: "gb", value: 100}])
          )
          expect(Utils::ActivityLog).to have_received(:produce).with(
            changed_entitlement, "plan_entitlement.updated", after_commit: true,
            changes: {"values" => [[{privilege_code: "max", value: 10}], [{privilege_code: "max", value: 25}]]},
            activity_object: hash_including(lago_id: changed_entitlement.id, values: [{privilege_code: "max", value: 25}])
          )
          expect(Utils::ActivityLog).to have_received(:produce).with(
            old_entitlement, "plan_entitlement.deleted", after_commit: true,
            changes: {"values" => [[{privilege_code: "provider", value: "okta"}], nil]},
            activity_object: hash_including(lago_id: old_entitlement.id, values: [{privilege_code: "provider", value: "okta"}])
          )
          expect(Utils::ActivityLog).to have_received(:produce).exactly(3).times
        end

        it "sends one webhook of the matching type for each changed entitlement, in one bulk push" do
          bulk_pushes = []
          ActiveSupport::Notifications.subscribed(->(event) { bulk_pushes << event.payload[:jobs].size }, "enqueue_all.active_job") do
            expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).exactly(3).times
          end

          added_entitlement = plan.entitlements.find_by!(feature: storage_feature)
          expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.created", added_entitlement)
          expect(SendWebhookJob).to have_been_enqueued.with("plan_entitlement.updated", changed_entitlement)
          expect(SendWebhookJob).to have_been_enqueued
            .with("plan_entitlement.deleted", old_entitlement, {values: [{privilege_code: "provider", value: "okta"}]})
          expect(bulk_pushes).to eq([3])
        end

        context "when the organization has no webhook endpoint" do
          before { organization.webhook_endpoints.destroy_all }

          it "enqueues no webhook" do
            expect { result }.not_to have_enqueued_job(SendWebhookJob)
          end
        end
      end

      context "when the replace changes nothing" do
        let(:entitlements_params) { {"sso" => {"provider" => "okta"}} }

        it "writes no activity log and sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(result.entitlements).to eq([old_entitlement])
          expect(Utils::ActivityLog).not_to have_received(:produce)
        end
      end

      context "when entitlements are kept" do
        let(:storage_feature) { create(:feature, organization:, code: "storage") }
        let(:recent_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature: storage_feature) }
        let(:older_entitlement) do
          create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature:, created_at: 1.day.ago)
        end
        let(:entitlements_params) { {"storage" => {}, "seats" => {}} }

        before do
          # Inserted in the order they were created, the reverse of the result: the order comes from created_at.
          older_entitlement
          recent_entitlement
        end

        it "returns them newest first" do
          expect(result.entitlements).to eq([recent_entitlement, older_entitlement])
        end
      end

      context "when activity logs are sent for several changed entitlements", :capture_kafka_messages do
        let(:storage_feature) { create(:feature, organization:, code: "storage") }
        let(:storage_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature: storage_feature) }
        let(:entitlements_params) do
          {"seats" => {"max" => 25, "provider" => "okta"}, "storage" => {"gb" => 200, "region" => "eu"}}
        end

        let(:queries_after_commit) { [] }

        before do
          allow(Utils::ActivityLog).to receive(:available?).and_return(true)
          allow(::V2::PlanEntitlementSerializer).to receive(:new).and_call_original
          # The logs are sent from after-commit callbacks: the queries they run are tracked apart.
          allow(AfterCommitEverywhere).to receive(:after_commit).and_wrap_original do |original, *args, &callback|
            original.call(*args) do
              track = ->(*, payload) { queries_after_commit << payload[:sql] }
              ActiveSupport::Notifications.subscribed(track, "sql.active_record", &callback)
            end
          end
          gb = create(:privilege, organization:, feature: storage_feature, code: "gb", value_type: "integer")
          region = create(:privilege, organization:, feature: storage_feature, code: "region", value_type: "string")
          create(:entitlement_value, organization:, entitlement: storage_entitlement, privilege: gb, value: "100")
          create(:entitlement_value, organization:, entitlement: storage_entitlement, privilege: region, value: "us")
        end

        it "logs each entitlement with the render built in the transaction, without loading its values again" do
          result

          expect(queries_after_commit.grep(/entitlement_entitlement_values|entitlement_privileges/)).to be_empty

          activity_objects = kafka_messages.map { JSON.parse(it[:payload]) }.to_h { [it["activity_type"], it["activity_object"]] }
          entitlement = storage_entitlement.reload
          expect(activity_objects.keys).to match_array(%w[plan_entitlement.created plan_entitlement.updated plan_entitlement.deleted])
          expect(activity_objects["plan_entitlement.updated"]).to eq(
            "lago_id" => entitlement.id,
            "plan_code" => plan.code,
            "feature_code" => "storage",
            # Newest privilege first: region is created after gb.
            "values" => [{"privilege_code" => "region", "value" => "eu"}, {"privilege_code" => "gb", "value" => 200}],
            "created_at" => entitlement.created_at.iso8601,
            "updated_at" => entitlement.updated_at.iso8601,
            "deleted_at" => nil
          )
          # Two renders of the kept entitlements before the call (storage, sso), three after (seats, storage, sso).
          expect(::V2::PlanEntitlementSerializer).to have_received(:new).exactly(5).times
        end
      end

      context "when the catalog plan is discarded" do
        let(:plan) { create(:catalog_plan, organization:, deleted_at: Time.current) }

        it "returns not found failure and writes nothing" do
          expect { result }.not_to change(Entitlement::Entitlement, :count)

          expect(result).not_to be_success
          expect(result.error.error_code).to eq("plan_not_found")
          expect(old_entitlement.reload).not_to be_discarded
          expect(Utils::ActivityLog).not_to have_received(:produce)
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end

      context "with the catalog plan limits" do
        let(:string_privilege) { nil }
        let(:boolean_privilege) { nil }
        let(:select_privilege) { nil }
        let(:bulk_feature_count) { 0 }
        let(:planned_feature_count) { 0 }
        let(:bulk_features) { bulk_create_features(organization, bulk_feature_count) }
        # rubocop:disable Rails/SkipsModelValidations
        # The entitlements the plan holds before the write: the first planned_feature_count bulk features.
        let(:planned_entitlements) do
          now = Time.current
          rows = bulk_features.values.first(planned_feature_count).map do |feature_id|
            {organization_id: organization.id, catalog_plan_id: plan.id, entitlement_feature_id: feature_id, created_at: now, updated_at: now}
          end
          Entitlement::Entitlement.insert_all!(rows) if rows.any?
        end
        # rubocop:enable Rails/SkipsModelValidations
        # max and 50 more integer privileges: 51 privileges on seats.
        let(:more_privileges) { create_list(:privilege, 50, organization:, feature:, value_type: "integer") }
        let(:seats_privileges) { [privilege, *more_privileges] }
        let(:seats_value_count) { 0 }
        let(:seats_params) { seats_privileges.first(seats_value_count).to_h { [it.code, 1] } }
        let(:entitlements_params) do
          params = bulk_features.keys.index_with { {} }
          (seats_value_count > 0) ? params.merge("seats" => seats_params) : params
        end

        before do
          bulk_features
          planned_entitlements
          more_privileges
        end

        shared_examples "a refused write" do
          it "writes nothing and logs no activity" do
            expect { result }
              .to not_change(Entitlement::Entitlement.with_discarded, :count)
              .and not_change(Entitlement::EntitlementValue.with_discarded, :count)

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.failed_field).to be_nil
            expect(old_entitlement.reload).not_to be_discarded
            expect(old_value.reload).to have_attributes(value: "okta", deleted_at: nil)
            expect(Utils::ActivityLog).not_to have_produced("plan.updated")
          end
        end

        context "with 200 entitlements after the replace" do
          let(:bulk_feature_count) { 200 }

          it "accepts them" do
            expect(result).to be_success
            expect(plan.entitlements.count).to eq(200) # 200 features of the body, sso dropped
            expect(old_entitlement.reload).to be_discarded
          end
        end

        context "with 201 entitlements after the replace" do
          let(:bulk_feature_count) { 201 }

          it_behaves_like "a refused write"

          it "refuses it before any write" do
            allow(Entitlement::Entitlement).to receive(:create!).and_call_original

            result

            expect(Entitlement::Entitlement).not_to have_received(:create!)
          end

          it "returns too_many_entitlements on base" do
            expect(result.error.messages).to eq(base: ["too_many_entitlements"])
            expect(result.error.codes).to eq(base: ["too_many_entitlements"])
            expect(result.error.meta).to eq(base: {max_items: 200})
          end
        end

        context "with 50 values on an entitlement" do
          let(:seats_value_count) { 50 }

          it "accepts them" do
            expect(result).to be_success
            expect(plan.entitlements.sole.values.count).to eq(50)
          end
        end

        context "with 51 values on an entitlement" do
          let(:seats_value_count) { 51 }

          it_behaves_like "a refused write"

          it "returns too_many_values on the entitlement" do
            expect(result.error.messages).to eq("entitlements.seats": ["too_many_values"])
            expect(result.error.codes).to eq("entitlements.seats": ["too_many_values"])
            expect(result.error.meta).to eq("entitlements.seats": {max_items: 50})
          end
        end

        context "with both limits crossed" do
          let(:bulk_feature_count) { 201 }
          let(:seats_value_count) { 51 }

          it_behaves_like "a refused write"

          it "returns too_many_entitlements alone, refused before the values are written" do
            expect(result.error.messages).to eq(base: ["too_many_entitlements"])
            expect(result.error.meta).to eq(base: {max_items: 200})
          end
        end

        context "with several entitlements over 50 values" do
          let(:storage_feature) { create(:feature, organization:, code: "storage") }
          let(:storage_privileges) { create_list(:privilege, 51, organization:, feature: storage_feature, value_type: "integer") }
          let(:seats_value_count) { 51 }
          let(:entitlements_params) do
            {"storage" => storage_privileges.to_h { [it.code, 1] }, "api" => {}, "seats" => seats_params}
          end

          before { create(:feature, organization:, code: "api") }

          it "returns too_many_values on each of them, in the order of the request" do
            expect(result.error.messages).to eq("entitlements.storage": ["too_many_values"], "entitlements.seats": ["too_many_values"])
            expect(result.error.messages.keys).to eq([:"entitlements.storage", :"entitlements.seats"])
          end
        end

        context "when the plan already holds more than 200 entitlements" do
          let(:old_value) { nil }
          let(:bulk_feature_count) { 202 }
          let(:planned_feature_count) { 201 }

          context "when the replace keeps them" do
            let(:entitlements_params) { bulk_features.keys.first(201).index_with { {} } }

            it "accepts it" do
              expect(result).to be_success
              expect(plan.entitlements.count).to eq(201)
            end
          end

          context "when the replace adds one" do
            it "refuses it" do
              expect { result }.not_to change(Entitlement::Entitlement.with_discarded, :count)

              expect(result.error.messages).to eq(base: ["too_many_entitlements"])
            end
          end

          context "when the replace drops entitlements but stays above 200" do
            let(:planned_feature_count) { 202 }
            let(:entitlements_params) { bulk_features.keys.first(201).index_with { {} } }

            it "accepts it" do
              expect(plan.entitlements.count).to eq(202)

              expect(result).to be_success
              expect(plan.entitlements.count).to eq(201) # 202 held - bulk_201 dropped
            end
          end
        end

        context "when the entitlement already holds 50 values and the replace rewrites them" do
          let(:old_value) { nil }
          let(:seats_owner) { plan }
          let(:seats_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: seats_owner, feature:) }
          let(:seats_value_count) { 50 }

          before do
            now = Time.current
            rows = seats_privileges.first(50).map do |seats_privilege|
              {organization_id: organization.id, entitlement_entitlement_id: seats_entitlement.id,
               entitlement_privilege_id: seats_privilege.id, value: "1", created_at: now, updated_at: now}
            end
            Entitlement::EntitlementValue.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
          end

          it "accepts the same 50 values" do
            expect(result).to be_success
            expect(seats_entitlement.values.count).to eq(50)
          end

          context "when the replace swaps one value for another" do
            # Drops the value of the first privilege and adds the 51st: 50 kept values and 1 discarded.
            let(:seats_params) { seats_privileges.drop(1).to_h { [it.code, 1] } }

            it "accepts it" do
              expect(result).to be_success
              expect(seats_entitlement.values.count).to eq(50)
              expect(Entitlement::EntitlementValue.with_discarded.where(entitlement: seats_entitlement).count).to eq(51)
            end
          end

          context "when another catalog plan holds the 50 values" do
            let(:seats_owner) { other_plan }
            let(:seats_value_count) { 1 }

            it "accepts a value on the plan" do
              expect(result).to be_success
              expect(plan.entitlements.sole.values.count).to eq(1)
            end
          end
        end

        context "when an entitlement already holds more than 50 values" do
          let(:old_value) { nil }
          let(:seats_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan: plan, feature:) }
          let(:seats_value_count) { 51 }

          before do
            now = Time.current
            rows = seats_privileges.map do |seats_privilege|
              {organization_id: organization.id, entitlement_entitlement_id: seats_entitlement.id,
               entitlement_privilege_id: seats_privilege.id, value: "1", created_at: now, updated_at: now}
            end
            Entitlement::EntitlementValue.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
          end

          it "accepts a replace that keeps them" do
            expect(result).to be_success
            expect(seats_entitlement.values.count).to eq(51)
          end

          context "when the replace adds one" do
            let(:extra_privilege) { create(:privilege, organization:, feature:, code: "extra", value_type: "integer") }
            let(:entitlements_params) { {"seats" => seats_params.merge(extra_privilege.code => 1)} }

            it "refuses it" do
              expect { result }.not_to change(Entitlement::EntitlementValue.with_discarded, :count)

              expect(result.error.messages).to eq("entitlements.seats": ["too_many_values"])
            end
          end
        end

        context "with a legacy plan" do
          let(:plan) { create(:plan, organization:) }
          let(:old_value) { nil }
          let(:bulk_feature_count) { 201 }
          let(:seats_value_count) { 51 }

          it "has no limit" do
            expect(result).to be_success
            expect(plan.entitlements.count).to eq(202) # 201 bulk features + seats
            expect(plan.entitlements.joins(:feature).find_by!(feature: {code: "seats"}).values.count).to eq(51)
          end
        end
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
