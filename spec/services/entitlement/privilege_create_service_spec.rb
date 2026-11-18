# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PrivilegeCreateService do
  subject(:result) { described_class.call(feature:, params:) }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:params) { {code: "max_admins", name: "Max admins", value_type: "integer"} }

  shared_examples "a failure that creates nothing" do
    it "creates no privilege and sends no webhook" do
      expect { result }.to not_change(Entitlement::Privilege.unscoped, :count)
        .and not_have_enqueued_job(SendWebhookJob)
      expect(Utils::ActivityLog).not_to have_produced("feature.updated")
    end
  end

  shared_examples "a validation failure" do |messages, meta = nil|
    it "returns a validation failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(messages)
      expect(result.error.meta).to eq(meta) if meta
    end

    it_behaves_like "a failure that creates nothing"
  end

  describe "#call", :premium do
    it "creates the privilege on the feature" do
      expect { result }.to change(feature.privileges, :count).by(1)

      expect(result).to be_success
      expect(result.privilege).to have_attributes(
        organization_id: organization.id,
        entitlement_feature_id: feature.id,
        code: "max_admins",
        name: "Max admins",
        value_type: "integer",
        config: {}
      )
      expect(result.privilege).to be_persisted
    end

    it "sends a feature.updated webhook" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
    end

    it "produces a feature.updated activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
    end

    %w[integer string boolean].each do |type|
      context "when value_type is #{type}" do
        let(:params) { {code: "max_admins", value_type: type} }

        it "creates the privilege with an empty config" do
          expect(result).to be_success
          expect(result.privilege).to have_attributes(value_type: type, config: {}, name: nil)
        end
      end
    end

    context "when value_type is select" do
      let(:params) { {code: "level", value_type: "select", select_options: ["low", "high"]} }

      it "stores the options in the config" do
        expect(result).to be_success
        expect(result.privilege).to have_attributes(value_type: "select", config: {"select_options" => ["low", "high"]})
      end
    end

    context "when value_type is absent" do
      let(:params) { {code: "max_admins"} }

      it "defaults to string" do
        expect(result).to be_success
        expect(result.privilege.value_type).to eq("string")
      end
    end

    context "when value_type is nil" do
      let(:params) { {code: "max_admins", value_type: nil} }

      it "defaults to string" do
        expect(result).to be_success
        expect(result.privilege.value_type).to eq("string")
      end
    end

    context "when the code has surrounding spaces" do
      let(:params) { {code: "  max_admins  "} }

      it "strips the code" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when feature is nil" do
      let(:feature) { nil }

      it "returns a not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end

      it_behaves_like "a failure that creates nothing"
    end

    context "when the feature is discarded between its lookup and the lock" do
      before do
        feature
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Feature.find(feature.id).discard!
      end

      it "returns a not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end

      it_behaves_like "a failure that creates nothing"
    end

    context "when value_type is unknown" do
      let(:params) { {code: "max_admins", value_type: "float"} }

      it_behaves_like "a validation failure", {value_type: ["value_is_invalid"]}
    end

    context "when value_type is not a string" do
      let(:params) { {code: "max_admins", value_type: 1} }

      it_behaves_like "a validation failure", {value_type: ["value_is_invalid"]}
    end

    context "when value_type is false" do
      let(:params) { {code: "max_admins", value_type: false} }

      it_behaves_like "a validation failure", {value_type: ["value_is_invalid"]}
    end

    context "when value_type is select and select_options are absent" do
      let(:params) { {code: "level", value_type: "select"} }

      it_behaves_like "a validation failure", {select_options: ["invalid_format"]}
    end

    [["empty", []], ["null", nil], ["not strings", [1, 2]]].each do |label, select_options|
      context "when value_type is select and select_options are #{label}" do
        let(:params) { {code: "level", value_type: "select", select_options:} }

        it_behaves_like "a validation failure", {select_options: ["invalid_format"]}
      end
    end

    context "when select_options are sent with another value_type" do
      let(:params) { {code: "level", value_type: "string", select_options: ["a"]} }

      it "ignores them" do
        expect(result).to be_success
        expect(result.privilege).to have_attributes(value_type: "string", config: {})
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, code|
      context "when code is #{label}" do
        let(:params) { {code:} }

        it_behaves_like "a validation failure", {code: ["value_is_invalid"]}
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, name|
      context "when name is #{label}" do
        let(:params) { {code: "max_admins", name:} }

        it_behaves_like "a validation failure", {name: ["value_is_invalid"]}
      end
    end

    context "when code is blank" do
      let(:params) { {code: "  "} }

      it_behaves_like "a validation failure", {code: ["value_is_mandatory"]}
    end

    context "when code is absent" do
      let(:params) { {name: "Max admins"} }

      it_behaves_like "a validation failure", {code: ["value_is_mandatory"]}
    end

    context "when code is too long" do
      let(:params) { {code: "a" * 256} }

      it_behaves_like "a validation failure", {code: ["value_is_too_long"]}, {code: {max_length: 255}}
    end

    context "when name is too long" do
      let(:params) { {code: "max_admins", name: "a" * 256} }

      it_behaves_like "a validation failure", {name: ["value_is_too_long"]}, {name: {max_length: 255}}
    end

    context "when the code is used by a kept privilege of the feature, as after a concurrent create" do
      # The model has no uniqueness validation, so a kept privilege with the code stands for the winner:
      # the insert reaches idx_privileges_code_unique_per_feature.
      before { create(:privilege, feature:, organization:, code: "max_admins") }

      it_behaves_like "a validation failure", {code: ["value_already_exist"]}
    end

    context "when another unique index is violated" do
      before do
        allow_any_instance_of(Entitlement::Privilege).to receive(:save!) # rubocop:disable RSpec/AnyInstance
          .and_raise(ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint \"other_index\"")
      end

      it "raises the violation" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "when the code is used by a discarded privilege of the feature" do
      before { create(:privilege, feature:, organization:, code: "max_admins", deleted_at: Time.current) }

      it "creates the privilege" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when the code is used on another feature" do
      before { create(:privilege, organization:, feature: create(:feature, organization:), code: "max_admins") }

      it "creates the privilege" do
        expect(result).to be_success
        expect(result.privilege.code).to eq("max_admins")
      end
    end

    context "when the feature has 49 privileges" do
      before { create_list(:privilege, 49, feature:, organization:) }

      it "creates the 50th privilege" do
        expect(result).to be_success
        expect(feature.privileges.count).to eq(50)
      end
    end

    context "when two creates run at the same time on a feature with 49 privileges", transaction: false do
      before { create_list(:privilege, 49, feature:, organization:) }

      it "creates only one of them" do
        paused = Queue.new
        resume = Queue.new
        first_call = Queue.new
        first_call << true

        # The first create waits after its count, while holding the lock.
        allow_any_instance_of(described_class).to receive(:attributes).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          if first_call.pop(timeout: 0)
            paused << true
            resume.pop
          end

          original.call(*args)
        end

        create_privilege = lambda do |code|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(feature: Entitlement::Feature.find(feature.id), params: {code:})
            end
          end
        end

        first = create_privilege.call("first")
        paused.pop
        second = create_privilege.call("second")
        sleep 0.5
        resume << true

        results = [first.value, second.value]

        expect(results.count(&:success?)).to eq(1)
        expect(results.reject(&:success?).map { |r| r.error.messages }).to eq([{base: ["too_many_privileges"]}])
        expect(feature.privileges.count).to eq(50)
      end
    end

    context "when the feature has 50 kept privileges" do
      before { create_list(:privilege, 50, feature:, organization:) }

      it_behaves_like "a validation failure", {base: ["too_many_privileges"]}, {base: {max_items: 50}}
    end

    context "when the feature has 50 privileges of which one is discarded" do
      before do
        create_list(:privilege, 49, feature:, organization:)
        create(:privilege, feature:, organization:, deleted_at: Time.current)
      end

      it "creates the privilege" do
        expect(result).to be_success
        expect(feature.privileges.count).to eq(50)
      end
    end
  end
end
