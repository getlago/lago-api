# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PrivilegeUpdateService do
  subject(:result) { described_class.call(feature:, privilege_code:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:feature, refind: true) { create(:feature, organization:, code: "sso") }

  let(:privilege) do
    create(
      :privilege,
      feature:,
      organization:,
      code: "provider",
      name: "Provider",
      value_type: "select",
      config: {"select_options" => %w[okta google entra_id]}
    )
  end
  let(:privilege_code) { "provider" }
  let(:params) { {name: "SSO provider", select_options: %w[okta google entra_id onelogin]} }

  before { privilege }

  shared_examples "a failure that changes nothing" do
    it "changes nothing and sends no webhook" do
      expect { result }.to not_have_enqueued_job(SendWebhookJob)
      expect(privilege.reload).to have_attributes(
        code: "provider",
        name: "Provider",
        value_type: "select",
        config: {"select_options" => %w[okta google entra_id]}
      )
      expect(Utils::ActivityLog).not_to have_produced("feature.updated")
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "plan.updated", any_args)
    end
  end

  shared_examples "a validation failure" do |messages|
    it "returns a validation failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(messages)
    end

    it_behaves_like "a failure that changes nothing"
  end

  shared_examples "a not found failure" do |resource|
    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq(resource)
    end
  end

  describe "#call", :premium do
    it "renames the privilege and stores the options in the order sent" do
      expect(result).to be_success
      expect(result.privilege).to eq(privilege)
      expect(privilege.reload).to have_attributes(
        code: "provider",
        name: "SSO provider",
        value_type: "select",
        config: {"select_options" => %w[okta google entra_id onelogin]}
      )
    end

    it "sends a feature.updated webhook" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
    end

    it "produces a feature.updated activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
    end

    context "when the options are sent in another order" do
      let(:params) { {select_options: %w[onelogin entra_id okta google]} }

      it "keeps the order sent" do
        expect(result).to be_success
        expect(privilege.reload.config).to eq({"select_options" => %w[onelogin entra_id okta google]})
      end
    end

    context "when only the name is sent" do
      let(:params) { {name: "SSO provider"} }

      it "changes the name and keeps the options" do
        expect(result).to be_success
        expect(privilege.reload).to have_attributes(
          name: "SSO provider",
          config: {"select_options" => %w[okta google entra_id]}
        )
      end
    end

    context "when the name is null" do
      let(:params) { {name: nil} }

      it "clears the name" do
        expect(result).to be_success
        expect(privilege.reload).to have_attributes(name: nil, config: {"select_options" => %w[okta google entra_id]})
      end
    end

    context "when params are empty" do
      let(:params) { {} }

      it "changes nothing and still sends a feature.updated webhook" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
        expect(result).to be_success
        expect(privilege.reload).to have_attributes(name: "Provider", config: {"select_options" => %w[okta google entra_id]})
      end
    end

    context "when the feature is attached to plans" do
      let(:entitlement) { create(:entitlement, feature:, organization:) }
      let(:other_entitlement) { create(:entitlement, feature:, organization:) }
      let(:discarded_plan_entitlement) do
        create(:entitlement, feature:, organization:, plan: create(:plan, organization:, deleted_at: Time.current))
      end

      before do
        entitlement
        other_entitlement
        discarded_plan_entitlement
      end

      it "sends one plan.updated webhook per kept plan" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
        expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", other_entitlement.plan).once
        expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", discarded_plan_entitlement.plan)
      end

      it "produces one plan.updated activity log per kept plan" do
        result
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(entitlement.plan)
        expect(Utils::ActivityLog).to have_received(:produce)
          .with(other_entitlement.plan, "plan.updated", after_commit: true).once
        expect(Utils::ActivityLog).not_to have_received(:produce)
          .with(discarded_plan_entitlement.plan, "plan.updated", any_args)
      end

      context "when params are empty" do
        let(:params) { {} }

        it "still sends plan.updated" do
          expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
          expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(entitlement.plan)
        end
      end

      context "when the update is refused" do
        let(:params) { {select_options: %w[okta]} }

        it_behaves_like "a validation failure", {select_options: ["select_option_removal_not_allowed"]}
      end
    end

    context "when select_options omit a current option" do
      let(:params) { {name: "SSO provider", select_options: %w[okta google]} }

      it_behaves_like "a validation failure", {select_options: ["select_option_removal_not_allowed"]}
    end

    context "when an option was added after the feature was loaded" do
      let(:params) { {select_options: %w[okta google entra_id onelogin]} }

      before do
        feature.privileges.load
        # Another update stored `x` since the caller looked the feature up.
        Entitlement::Privilege.where(id: privilege.id)
          .update_all(config: {"select_options" => %w[okta google entra_id x]}, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end

      it "refuses a request that omits it" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({select_options: ["select_option_removal_not_allowed"]})
        expect(privilege.reload.config).to eq({"select_options" => %w[okta google entra_id x]})
      end

      it "sends no webhook" do
        expect { result }.to not_have_enqueued_job(SendWebhookJob)
      end
    end

    context "when another update adds an option while the service waits for the lock" do
      let(:params) { {select_options: %w[okta google entra_id onelogin]} }

      before do
        allow(feature).to receive(:with_lock).and_wrap_original do |original, *args, &block|
          # The other update held the lock and committed `x` before this one gets it.
          Entitlement::Privilege.where(id: privilege.id)
            .update_all(config: {"select_options" => %w[okta google entra_id x]}, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          original.call(*args, &block)
        end
      end

      it "refuses a request that omits it and sends no webhook" do
        expect { result }.to not_have_enqueued_job(SendWebhookJob)
        expect(result).to be_failure
        expect(result.error.messages).to eq({select_options: ["select_option_removal_not_allowed"]})
        expect(privilege.reload.config).to eq({"select_options" => %w[okta google entra_id x]})
      end
    end

    context "when the code differs" do
      let(:params) { {code: "other"} }

      it_behaves_like "a validation failure", {code: ["value_is_immutable"]}
    end

    context "when the code is null" do
      let(:params) { {code: nil} }

      it_behaves_like "a validation failure", {code: ["value_is_immutable"]}
    end

    context "when the code is the current one with surrounding spaces" do
      let(:params) { {code: "  provider  ", name: "SSO provider"} }

      it "updates the privilege" do
        expect(result).to be_success
        expect(privilege.reload).to have_attributes(code: "provider", name: "SSO provider")
      end
    end

    context "when the value_type differs" do
      let(:params) { {value_type: "string"} }

      it_behaves_like "a validation failure", {value_type: ["value_is_immutable"]}
    end

    context "when the value_type is unknown" do
      let(:params) { {value_type: "float"} }

      it_behaves_like "a validation failure", {value_type: ["value_is_immutable"]}
    end

    context "when the value_type is the current one" do
      let(:params) { {value_type: "select", name: "SSO provider"} }

      it "updates the privilege" do
        expect(result).to be_success
        expect(privilege.reload).to have_attributes(value_type: "select", name: "SSO provider")
      end
    end

    context "when both code and value_type differ" do
      let(:params) { {code: "other", value_type: "string"} }

      it_behaves_like "a validation failure", {code: ["value_is_immutable"]}
    end

    context "when select_options are null" do
      let(:params) { {select_options: nil} }

      it_behaves_like "a validation failure", {select_options: ["select_option_removal_not_allowed"]}
    end

    context "when select_options are empty" do
      let(:params) { {select_options: []} }

      it_behaves_like "a validation failure", {select_options: ["select_option_removal_not_allowed"]}
    end

    context "when select_options are not strings" do
      let(:params) { {select_options: ["okta", "google", "entra_id", 1]} }

      it_behaves_like "a validation failure", {select_options: ["invalid_format"]}
    end

    context "when the privilege is not a select" do
      let(:privilege) { create(:privilege, feature:, organization:, code: "provider", name: "Provider", value_type: "string") }

      context "when select_options are sent" do
        let(:params) { {select_options: ["okta"]} }

        it "ignores them" do
          expect(result).to be_success
          expect(privilege.reload).to have_attributes(name: "Provider", config: {})
        end
      end

      context "when select_options are null" do
        let(:params) { {name: "SSO provider", select_options: nil} }

        it "updates the name and keeps an empty config" do
          expect(result).to be_success
          expect(privilege.reload).to have_attributes(name: "SSO provider", config: {})
        end
      end

      context "when only the name is sent" do
        let(:params) { {name: "SSO provider"} }

        it "updates the name" do
          expect(result).to be_success
          expect(privilege.reload).to have_attributes(name: "SSO provider", config: {})
        end
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, value|
      context "when name is #{label}" do
        let(:params) { {name: value} }

        it_behaves_like "a validation failure", {name: ["value_is_invalid"]}
      end
    end

    [["a number", 123], ["a boolean", true]].each do |label, value|
      %i[code value_type].each do |field|
        context "when #{field} is #{label}" do
          let(:params) { {field => value} }

          it_behaves_like "a validation failure", {field => ["value_is_immutable"]}
        end
      end
    end

    context "when the name is too long" do
      let(:params) { {name: "a" * 256} }

      it_behaves_like "a validation failure", {name: ["value_is_too_long"]}
    end

    context "when feature is nil" do
      let(:feature) { nil }
      let(:privilege) { nil }

      it_behaves_like "a not found failure", "feature"

      it "sends no webhook" do
        expect { result }.to not_have_enqueued_job(SendWebhookJob)
      end
    end

    context "when the feature is discarded between its lookup and the lock" do
      before do
        feature
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Feature.find(feature.id).discard!
      end

      it_behaves_like "a not found failure", "feature"
      it_behaves_like "a failure that changes nothing"
    end

    context "when the privilege code is unknown" do
      let(:privilege_code) { "unknown" }

      it_behaves_like "a not found failure", "privilege"
      it_behaves_like "a failure that changes nothing"
    end

    context "when the privilege belongs to another feature" do
      let(:privilege) do
        create(:privilege, organization:, feature: create(:feature, organization:), code: "provider", value_type: "string")
      end

      it_behaves_like "a not found failure", "privilege"

      it "sends no webhook" do
        expect { result }.to not_have_enqueued_job(SendWebhookJob)
      end
    end

    context "when the privilege is discarded" do
      before { privilege.discard! }

      it_behaves_like "a not found failure", "privilege"

      it "keeps the discarded privilege unchanged and sends no webhook" do
        expect { result }.to not_have_enqueued_job(SendWebhookJob)
        expect(Entitlement::Privilege.unscoped.find(privilege.id)).to have_attributes(
          name: "Provider",
          config: {"select_options" => %w[okta google entra_id]}
        )
      end
    end
  end
end
