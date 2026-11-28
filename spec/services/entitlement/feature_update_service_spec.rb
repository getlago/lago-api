# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeatureUpdateService do
  subject { described_class.call(feature:, params:, partial:) }

  # A let, not let_it_be: before_all makes every thread share one connection, which the concurrency example cannot use.
  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege1) { create(:privilege, feature:, code: "max", name: "Maximum") }
  let(:privilege2) { create(:privilege, feature:, code: "min", name: "Minimum") }
  let(:privilege3) { create(:privilege, feature:, code: "opt", name: "Optional") }
  let(:params) { {} }
  let(:partial) { false }

  before do
    privilege1
    privilege2
    privilege3
  end

  describe "#call", :premium do
    [true, false].each do |partial_update|
      [
        ["a single object", {code: "max", name: "New", value_type: "boolean"}],
        ["an object with numeric keys", {"0" => {code: "max", name: "New"}, "1" => {code: "other"}}]
      ].each do |label, privileges|
        context "when privileges is #{label} and partial is #{partial_update}" do
          let(:partial) { partial_update }
          let(:params) { {name: "Updated Name", description: "Updated description", privileges:} }
          let(:entitlement) { create(:entitlement, feature:) }

          before { create(:entitlement_value, entitlement:, privilege: privilege1, value: 10) }

          it "returns value_is_invalid on privileges and changes nothing" do
            expect { subject }
              .to not_change { feature.reload.attributes.slice("name", "description") }
              .and not_change { feature.privileges.reload.pluck(:id, :code, :name) }
              .and not_have_enqueued_job(SendWebhookJob)

            expect(subject).to be_failure
            expect(subject.error).to be_a(BaseService::ValidationFailure)
            expect(subject.error.messages).to eq({privileges: ["value_is_invalid"]})
          end
        end
      end
    end

    context "when update is full" do
      let(:partial) { false }

      context "when privilege code is duplicated" do
        let(:params) do
          {
            code: "seats",
            privileges: [
              {code: "max_admins"},
              {code: "max_admins"}
            ]
          }
        end

        it "returns a validation failure" do
          result = subject

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
        end
      end

      context "when updating feature attributes" do
        let(:params) do
          {
            name: "Updated Feature Name",
            description: "Updated feature description"
          }
        end

        it "updates the feature name and description" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("Updated Feature Name")
          expect(result.feature.description).to eq("Updated feature description")
        end

        it "sends feature.updated webhook" do
          expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
        end

        it "produces an activity log" do
          result = subject
          expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(result.feature)
        end

        it "only updates provided attributes" do
          original_name = feature.name
          params.delete(:name)

          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq(original_name)
          expect(result.feature.description).to eq("Updated feature description")
        end
      end

      context "when updating privileges" do
        let(:params) do
          {
            privileges: [
              {code: "max", name: "Max."},
              {code: "min", name: "Min."}
            ]
          }
        end

        it "updates the privilege names and delete missing privileges" do
          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq("Max.")
          expect(privilege2.reload.name).to eq("Min.")
          expect(privilege3.reload.deleted_at).to be_present
          expect(feature.privileges.pluck(:code)).to match_array(%w[max min])
        end

        it "only updates provided privilege attributes" do
          original_name = privilege1.name
          params[:privileges] = [
            {code: "max"},
            {code: "min", name: "Min."}
          ]

          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq(original_name)
          expect(privilege2.reload.name).to eq("Min.")
        end
      end

      context "when updating both feature and privileges" do
        let(:params) do
          {
            name: "Updated Feature Name",
            description: "Updated feature description",
            privileges: [
              {code: "max", name: "Max."}
            ]
          }
        end

        it "updates both feature and privilege attributes" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("Updated Feature Name")
          expect(result.feature.description).to eq("Updated feature description")
          expect(privilege1.reload.name).to eq("Max.")
          expect(feature.privileges.reload.count).to eq(1)
          expect(feature.privileges.pluck(:code)).to eq(%w[max])
        end
      end

      context "when updating select_options of a privilege" do
        let(:privilege3) { create(:privilege, feature:, code: "opt", value_type: "select", config: {select_options: %w[zero one]}) }

        let(:params) do
          {
            privileges: [
              {code: "opt", config: {select_options: %w[one two three]}}
            ]
          }
        end

        it "appends the new options" do
          result = subject

          expect(result).to be_success
          expect(privilege3.reload.config["select_options"]).to eq %w[zero one two three]
        end
      end

      context "when deleting privileges with associated entitlement values" do
        let(:entitlement) { create(:entitlement, feature:) }
        let(:privilege1_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: "10") }
        let(:privilege2_value) { create(:entitlement_value, entitlement:, privilege: privilege2, value: "true") }
        let(:privilege3_value) { create(:entitlement_value, entitlement:, privilege: privilege3, value: "option1") }

        let(:params) do
          {
            privileges: [
              {code: "max", name: "Max."}
            ]
          }
        end

        before do
          privilege1_value
          privilege2_value
          privilege3_value
        end

        it "soft deletes entitlement values for removed privileges" do
          result = subject

          expect(result).to be_success
          expect(Entitlement::EntitlementValue.with_discarded.count).to eq(3)
          expect(Entitlement::EntitlementValue.count).to eq(1) # only privilege1_value remains
          expect(privilege1_value.reload).to be_present
          expect(privilege2_value.reload).to be_discarded
          expect(privilege3_value.reload).to be_discarded
        end

        it "soft deletes the removed privileges" do
          result = subject

          expect(result).to be_success
          expect(Entitlement::Privilege.with_discarded.count).to eq(3)
          expect(Entitlement::Privilege.count).to eq(1) # only privilege1 remains
          expect(privilege1.reload).to be_present
          expect(privilege2.reload).to be_discarded
          expect(privilege3.reload).to be_discarded
        end

        it "discards each removed privilege once" do
          discards = 0
          count_discards = ->(*, payload) { discards += 1 if payload[:sql].match?(/UPDATE "entitlement_privileges" SET "deleted_at"/) }

          ActiveSupport::Notifications.subscribed(count_discards, "sql.active_record") { subject }

          expect(discards).to eq(2) # min and opt
        end
      end

      context "when a privilege code is padded with spaces" do
        let(:privilege3) { create(:privilege, feature:, code: "opt", value_type: "select", config: {select_options: %w[zero one]}) }
        let(:plan_value) { create(:entitlement_value, entitlement: create(:entitlement, feature:), privilege: privilege3, value: "one") }
        let(:subscription_value) { create(:entitlement_value, entitlement: create(:entitlement, :subscription, feature:), privilege: privilege3, value: "zero") }
        let(:params) { {privileges: [{code: " opt ", name: "Opt."}]} }

        before do
          plan_value
          subscription_value
        end

        it "updates the stored privilege in place and keeps its entitlement values" do
          result = subject

          expect(result).to be_success
          expect(feature.privileges.reload.pluck(:id, :code, :name, :config)).to eq([
            [privilege3.id, "opt", "Opt.", {"select_options" => %w[zero one]}]
          ])
          expect(Entitlement::Privilege.with_discarded.count).to eq(3) # max and min discarded, no privilege created
          expect(Entitlement::EntitlementValue.where(privilege: privilege3)).to match_array([plan_value, subscription_value])
        end
      end

      context "when two privilege codes are equal once stripped" do
        let(:params) { {name: "Renamed", privileges: [{code: "max", name: "A"}, {code: " max ", name: "B"}]} }

        it "returns a validation failure and writes nothing" do
          result = subject

          expect(result).not_to be_success
          expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
          expect(feature.reload.name).not_to eq("Renamed")
          expect(Entitlement::Privilege.with_discarded.pluck(:id, :code, :name, :deleted_at)).to match_array([
            [privilege1.id, "max", "Maximum", nil],
            [privilege2.id, "min", "Minimum", nil],
            [privilege3.id, "opt", "Optional", nil]
          ])
        end
      end

      context "when deleting privileges with contract removals" do
        let(:contract) { create(:contract, organization:) }
        let(:removed_privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege: privilege2) }
        let(:kept_privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege: privilege1) }
        let(:subscription_removal) { create(:subscription_feature_removal, privilege: privilege2) }
        let(:params) do
          {
            privileges: [
              {code: "max", name: "Max."}
            ]
          }
        end

        before do
          removed_privilege_removal
          kept_privilege_removal
          subscription_removal
        end

        it "discards the contract removals of the removed privileges only" do
          freeze_time do
            expect(subject).to be_success

            expect(removed_privilege_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
            expect(kept_privilege_removal.reload.deleted_at).to be_nil
            expect(subscription_removal.reload.deleted_at).to be_nil
          end
        end
      end

      context "when new privileges is provided" do
        let(:new_privilege_code) { "     new_privilege     " }
        let(:params) do
          {
            privileges: [
              {code: new_privilege_code, name: "New Privilege"}
            ]
          }
        end

        it "creates a new privilege" do
          result = subject

          expect(result).to be_success
          expect(feature.privileges.reload.count).to eq(1)
          expect(feature.privileges.sole.code).to eq("new_privilege")
          expect(feature.privileges.sole.name).to eq("New Privilege")
          expect(feature.privileges.sole.value_type).to eq("string")
        end

        context "when new privilege params are invalid" do
          let(:params) do
            {
              privileges: [
                {code: new_privilege_code, name: "New Privilege", value_type: "invalid_type"}
              ]
            }
          end

          it "returns a validation failure" do
            result = subject

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to include("privilege.value_type": ["value_is_invalid"])
          end
        end
      end

      context "when the update keeps the 3 privileges and adds 47" do
        let(:params) { {privileges: [{code: "max"}, {code: "min"}, {code: "opt"}] + Array.new(47) { |i| {code: "new_#{i}"} }} }

        it "ends with 50 privileges" do
          expect(subject).to be_success
          expect(feature.privileges.count).to eq(50)
        end
      end

      context "when the update keeps the 3 privileges and adds 48" do
        let(:params) do
          {
            name: "Renamed",
            privileges: [{code: "max", name: "Max."}, {code: "min"}, {code: "opt"}] + Array.new(48) { |i| {code: "new_#{i}"} }
          }
        end

        it "returns too_many_privileges and writes nothing" do
          expect { subject }.not_to have_enqueued_job(SendWebhookJob)

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(subject.error.meta).to eq({base: {max_items: 50}})
          expect(feature.reload.name).not_to eq("Renamed")
          expect(feature.privileges.pluck(:code)).to match_array(%w[max min opt])
          expect(privilege1.reload.name).to eq("Maximum")
        end
      end

      context "when the update removes the 3 privileges and adds 50" do
        let(:params) { {privileges: Array.new(50) { |i| {code: "new_#{i}"} }} }

        it "counts the privileges after the removals" do
          expect(subject).to be_success
          expect(feature.privileges.count).to eq(50)
          expect(feature.privileges.where(code: %w[max min opt])).to be_empty
        end
      end

      context "when the update removes the 3 privileges and adds 51" do
        let(:params) { {privileges: Array.new(51) { |i| {code: "new_#{i}"} }} }

        it "returns too_many_privileges and keeps the removed privileges" do
          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(feature.reload.privileges.pluck(:code)).to match_array(%w[max min opt])
        end
      end

      context "when feature is nil" do
        let(:params) { {name: "Updated Name"} }

        it "returns a not found failure" do
          result = described_class.call(feature: nil, params:, partial:)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("feature")
        end
      end

      context "when the feature is discarded between its lookup and the lock" do
        let(:params) { {name: "Updated Name"} }

        before do
          feature
          # Another instance discards it, so the loaded one is stale.
          Entitlement::Feature.find(feature.id).discard!
        end

        it "returns a not found failure and does not rename the feature" do
          expect { subject }.not_to have_enqueued_job(SendWebhookJob)

          expect(subject).to be_failure
          expect(subject.error).to be_a(BaseService::NotFoundFailure)
          expect(subject.error.resource).to eq("feature")
          expect(Entitlement::Feature.unscoped.find(feature.id).name).not_to eq("Updated Name")
        end
      end

      context "when privilege name is empty" do
        let(:params) do
          {
            privileges: [
              {code: "max", name: ""} # Empty name is allowed
            ]
          }
        end

        it "updates the privilege name to empty string" do
          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq("")
        end
      end

      context "when feature name is empty" do
        let(:params) { {name: ""} }

        it "updates the feature name to empty string" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("")
        end
      end

      context "when feature is attached to a plan" do
        let(:params) { {} }
        let(:entitlement) { create(:entitlement, feature:) }
        let(:privilege1_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 10) }
        let(:privilege2_value) { create(:entitlement_value, entitlement:, privilege: privilege2, value: true) }

        before do
          privilege1_value
          privilege2_value
        end

        it "sends plan.updated webhook" do
          expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
        end

        it "produces plan.updated logs" do
          subject
          expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(entitlement.plan)
        end
      end

      shared_examples "discards all privileges" do
        it "discards all existing privileges" do
          result = subject

          expect(result).to be_success
          expect(feature.privileges.reload.count).to eq(0)
        end
      end

      context "when no privileges are provided" do
        let(:params) { {name: "Updated Name"} }

        it_behaves_like "discards all privileges"
      end

      context "when privileges parameter is empty hash" do
        let(:params) { {name: "Updated Name", privileges: {}} }

        it_behaves_like "discards all privileges"
      end

      context "when privileges parameter is nil" do
        let(:params) { {name: "Updated Name", privileges: nil} }

        it_behaves_like "discards all privileges"
      end
    end

    describe "when update is partial" do
      let(:partial) { true }

      context "when privilege code is duplicated" do
        let(:params) do
          {
            code: "seats",
            privileges: [
              {code: "max_admins"},
              {code: "max_admins"}
            ]
          }
        end

        it "returns a validation failure" do
          result = subject

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
        end
      end

      context "when updating feature attributes" do
        let(:params) do
          {
            name: "Updated Feature Name",
            description: "Updated feature description"
          }
        end

        it "updates the feature name and description" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("Updated Feature Name")
          expect(result.feature.description).to eq("Updated feature description")
        end

        it "sends feature.updated webhook" do
          expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
        end

        it "produces an activity log" do
          result = subject
          expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(result.feature)
        end

        it "only updates provided attributes" do
          original_name = feature.name
          params.delete(:name)

          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq(original_name)
          expect(result.feature.description).to eq("Updated feature description")
        end
      end

      context "when privileges with contract removals are not in the params" do
        let(:removal) { create(:subscription_feature_removal, :contract, privilege: privilege2) }
        let(:params) { {privileges: [{code: "max", name: "Max."}]} }

        before { removal }

        it "keeps the privileges and their contract removals" do
          expect(subject).to be_success

          expect(privilege2.reload).not_to be_discarded
          expect(removal.reload.deleted_at).to be_nil
        end
      end

      context "when updating privilege names" do
        let(:params) do
          {
            privileges: [
              {code: "max", name: "Max."},
              {code: "min", name: "Min."}
            ]
          }
        end

        it "updates the privilege names" do
          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq("Max.")
          expect(privilege2.reload.name).to eq("Min.")
        end

        it "only updates privileges that exist" do
          params[:privileges] << {code: "nonexistent", name: "New Name"}

          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq("Max.")
          expect(privilege2.reload.name).to eq("Min.")
        end

        it "only updates provided privilege attributes" do
          original_name = privilege1.name
          params[:privileges] = [
            {code: "max"},
            {code: "min", name: "Min."}
          ]

          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq(original_name)
          expect(privilege2.reload.name).to eq("Min.")
        end

        context "when the privilege code is padded with spaces" do
          let(:params) { {privileges: [{code: " max ", name: "Max."}]} }

          it "updates the stored privilege in place" do
            result = subject

            expect(result).to be_success
            expect(feature.privileges.reload.pluck(:id, :code, :name)).to match_array([
              [privilege1.id, "max", "Max."],
              [privilege2.id, "min", "Minimum"],
              [privilege3.id, "opt", "Optional"]
            ])
          end
        end
      end

      context "when updating select_options of a privilege" do
        let(:privilege3) { create(:privilege, feature:, code: "opt", value_type: "select", config: {select_options: %w[zero one]}) }

        let(:params) do
          {
            privileges: [
              {code: "opt", config: {select_options: %w[one two three]}}
            ]
          }
        end

        it "appends the new options" do
          result = subject

          expect(result).to be_success
          expect(privilege3.reload.config["select_options"]).to eq %w[zero one two three]
        end
      end

      context "when updating both feature and privileges" do
        let(:params) do
          {
            name: "Updated Feature Name",
            description: "Updated feature description",
            privileges: [
              {code: "max", name: "Max."}
            ]
          }
        end

        it "updates both feature and privilege attributes" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("Updated Feature Name")
          expect(result.feature.description).to eq("Updated feature description")
          expect(privilege1.reload.name).to eq("Max.")
          expect(privilege2.reload.name).to eq("Minimum") # unchanged
        end
      end

      context "when two privilege codes are equal once stripped" do
        let(:params) { {name: "Renamed", privileges: [{code: "max", name: "A"}, {code: " max ", name: "B"}]} }

        it "returns a validation failure and writes nothing" do
          result = subject

          expect(result).not_to be_success
          expect(result.error.messages[:"privilege.code"]).to eq ["value_is_duplicated"]
          expect(feature.reload.name).not_to eq("Renamed")
          expect(Entitlement::Privilege.with_discarded.pluck(:id, :code, :name, :deleted_at)).to match_array([
            [privilege1.id, "max", "Maximum", nil],
            [privilege2.id, "min", "Minimum", nil],
            [privilege3.id, "opt", "Optional", nil]
          ])
        end
      end

      context "when the update adds 47 privileges to the 3 existing ones" do
        let(:params) { {privileges: Array.new(47) { |i| {code: "new_#{i}"} }} }

        it "ends with 50 privileges" do
          expect(subject).to be_success
          expect(feature.privileges.count).to eq(50)
        end
      end

      context "when the update adds 48 privileges to the 3 existing ones" do
        let(:params) { {privileges: Array.new(48) { |i| {code: "new_#{i}"} }} }

        it "returns too_many_privileges and writes nothing" do
          expect { subject }.not_to have_enqueued_job(SendWebhookJob)

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(subject.error.meta).to eq({base: {max_items: 50}})
          expect(feature.reload.privileges.pluck(:code)).to match_array(%w[max min opt])
        end
      end

      context "when the update adds 51 privileges" do
        let(:params) { {privileges: Array.new(51) { |i| {code: "new_#{i}"} }} }

        it "refuses it before the lock and creates no privilege" do
          allow(feature).to receive(:lock!).and_call_original

          expect { subject }.not_to change(Entitlement::Privilege, :count)

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(subject.error.meta).to eq({base: {max_items: 50}})
          expect(feature).not_to have_received(:lock!)
        end
      end

      context "when the 50 new codes alone reach the limit on a feature that already has privileges" do
        let(:params) { {privileges: Array.new(50) { |i| {code: "new_#{i}"} }} }

        it "passes the early check and is refused by the exact count" do
          allow(feature).to receive(:lock!).and_call_original

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(feature).to have_received(:lock!)
          expect(feature.reload.privileges.pluck(:code)).to match_array(%w[max min opt])
        end
      end

      context "when 51 codes are sent but 2 already exist" do
        let(:params) { {privileges: [{code: "max"}, {code: "min"}] + Array.new(47) { |i| {code: "new_#{i}"} }} }

        it "counts only the new codes" do
          expect(subject).to be_success
          expect(feature.privileges.count).to eq(50)
        end
      end

      context "when 51 codes are sent and 3 of them are padded codes of existing privileges" do
        let(:params) { {privileges: [{code: " max "}, {code: " min"}, {code: "opt "}] + Array.new(48) { |i| {code: "new_#{i}"} }} }

        it "does not count the padded codes as new in the early check" do
          allow(feature).to receive(:lock!).and_call_original

          expect(subject).to be_failure
          expect(subject.error.messages).to eq({base: ["too_many_privileges"]})
          expect(feature).to have_received(:lock!)
        end
      end

      context "when the feature is already above the limit and the update adds no privilege" do
        let(:params) { {name: "Renamed", privileges: [{code: "max", name: "Max."}]} }

        before { create_list(:privilege, 48, feature:) }

        it "updates the feature" do
          expect(subject).to be_success
          expect(feature.reload.name).to eq("Renamed")
          expect(privilege1.reload.name).to eq("Max.")
          expect(feature.privileges.count).to eq(51)
        end
      end

      context "when two updates add the 50th privilege at the same time", transaction: false do
        before { create_list(:privilege, 46, feature:, organization:) }

        it "applies only one of them" do
          paused = Queue.new
          resume = Queue.new
          first_call = Queue.new
          first_call << true

          # The first update waits after its count, while holding the feature lock.
          allow_any_instance_of(described_class).to receive(:check_privileges_limit!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
            original.call(*args)

            if first_call.pop(timeout: 0)
              paused << true
              resume.pop
            end
          end

          add_privilege = lambda do |code|
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                described_class.call(feature: Entitlement::Feature.find(feature.id), params: {privileges: [{code:}]}, partial: true)
              end
            end
          end

          first = add_privilege.call("first")
          paused.pop
          second = add_privilege.call("second")
          sleep 0.5
          resume << true

          results = [first.value, second.value]

          expect(results.count(&:success?)).to eq(1)
          expect(results.reject(&:success?).map { |r| r.error.messages }).to eq([{base: ["too_many_privileges"]}])
          expect(feature.privileges.count).to eq(50)
        end
      end

      context "when feature is nil" do
        let(:params) { {name: "Updated Name"} }

        it "returns a not found failure" do
          result = described_class.call(feature: nil, params:, partial:)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("feature")
        end
      end

      context "when privilege name is empty" do
        let(:params) do
          {
            privileges: [
              {code: "max", name: ""} # Empty name is allowed
            ]
          }
        end

        it "updates the privilege name to empty string" do
          result = subject

          expect(result).to be_success
          expect(privilege1.reload.name).to eq("")
        end
      end

      context "when feature name is empty" do
        let(:params) { {name: ""} }

        it "updates the feature name to empty string" do
          result = subject

          expect(result).to be_success
          expect(result.feature.name).to eq("")
        end
      end

      context "when new privileges is provided" do
        let(:new_privilege_code) { "new_privilege" }
        let(:params) do
          {
            privileges: [
              {code: new_privilege_code, name: "New Privilege"}
            ]
          }
        end

        it "creates a new privilege" do
          result = subject

          expect(result).to be_success
          expect(feature.privileges.reload.count).to eq(4) # 3 existing + 1 new
          p = feature.privileges.find_by(code: new_privilege_code)
          expect(p.name).to eq("New Privilege")
          expect(p.value_type).to eq("string")
        end

        context "when new privilege params are invalid" do
          let(:params) do
            {
              privileges: [
                {code: new_privilege_code, name: "New Privilege", value_type: "invalid_type"}
              ]
            }
          end

          it "returns a validation failure" do
            result = subject

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to include("privilege.value_type": ["value_is_invalid"])
          end
        end
      end

      context "when feature is attached to a plan" do
        let(:params) { {} }
        let(:entitlement) { create(:entitlement, feature:) }
        let(:privilege1_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 10) }
        let(:privilege2_value) { create(:entitlement_value, entitlement:, privilege: privilege2, value: true) }

        before do
          privilege1_value
          privilege2_value
        end

        it "sends plan.updated webhook" do
          expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
        end

        it "produces plan.updated logs" do
          subject
          allow(Utils::ActivityLog).to receive(:produce_after_commit).and_call_original
        end
      end
    end
  end
end
