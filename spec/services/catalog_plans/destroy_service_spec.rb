# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(catalog_plan:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }
  let(:rate_override) { create(:rate_override, organization:) }
  let(:phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override:) }

  before { allow(Utils::ActivityLog).to receive(:produce) }

  it "soft deletes the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan).to be_discarded
    expect(organization.catalog_plans.kept).to be_empty
  end

  it "tears down the plan's rate cards, phases and overrides" do
    phase

    result

    expect(plan_rate_card.reload).to be_discarded
    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  it "publishes the shared plan.deleted event and legacy activity arguments" do
    phase

    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.deleted", catalog_plan)
    expect(Utils::ActivityLog).to have_received(:produce).with(catalog_plan, "plan.deleted", after_commit: true)
    expect(SendWebhookJob).not_to have_been_enqueued.with("plan_rate_card.deleted", anything, anything)
    expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "plan_rate_card.deleted", any_args)
    expect(catalog_plan.reload).to be_discarded
  end

  it "delivers legacy webhook and activity payloads after the plan is discarded", transaction: false do
    create(:webhook_endpoint, organization:)
    phase
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    perform_enqueued_jobs(only: SendWebhookJob) { result }

    webhook = Webhook.find_by!(webhook_type: "plan.deleted")
    expect(webhook.payload.fetch("plan").fetch("applied_rate_cards_count")).to eq(0)
    expect(webhook.payload.fetch("plan")).not_to have_key("applied_rate_cards")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "plan.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object")).not_to have_key("applied_rate_cards")
    expect(Webhook.where(webhook_type: "plan_rate_card.deleted")).not_to exist
  end

  context "with entitlements" do
    let(:feature) { create(:feature, organization:) }
    let(:privilege) { create(:privilege, organization:, feature:) }
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, feature:, catalog_plan:) }
    let(:entitlement_value) { create(:entitlement_value, organization:, entitlement:, privilege:) }
    let(:other_catalog_plan) { create(:catalog_plan, organization:) }
    let(:other_entitlement) { create(:entitlement, :catalog_plan, organization:, feature:, catalog_plan: other_catalog_plan) }
    let(:other_entitlement_value) { create(:entitlement_value, organization:, entitlement: other_entitlement, privilege:) }
    let(:legacy_plan) { create(:plan, organization:) }
    let(:legacy_entitlement) { create(:entitlement, organization:, feature:, plan: legacy_plan) }
    let(:legacy_entitlement_value) { create(:entitlement_value, organization:, entitlement: legacy_entitlement, privilege:) }

    before do
      entitlement_value
      other_entitlement_value
      legacy_entitlement_value
    end

    it "discards the plan's entitlements and their values" do
      travel_to(Time.zone.parse("2026-11-13 10:00:00")) do
        expect(result).to be_success

        discarded_entitlement = Entitlement::Entitlement.with_discarded.find(entitlement.id)
        discarded_value = Entitlement::EntitlementValue.with_discarded.find(entitlement_value.id)
        expect(discarded_entitlement.deleted_at).to eq(Time.current)
        expect(discarded_entitlement.updated_at).to eq(Time.current)
        expect(discarded_value.deleted_at).to eq(Time.current)
        expect(discarded_value.updated_at).to eq(Time.current)
      end
    end

    it "leaves the entitlements of other plans untouched" do
      result

      expect(other_entitlement.reload).not_to be_discarded
      expect(other_entitlement_value.reload).not_to be_discarded
      expect(legacy_entitlement.reload).not_to be_discarded
      expect(legacy_entitlement_value.reload).not_to be_discarded
    end

    context "when the plan is attached to contracts" do
      before { create(:contract, organization:, catalog_plan:) }

      it "discards no entitlement" do
        expect(result.error.messages[:plan]).to eq(["plan_locked"])
        expect(entitlement.reload).not_to be_discarded
        expect(entitlement_value.reload).not_to be_discarded
      end
    end
  end

  context "when the plan is discarded after it is loaded" do
    let(:entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:) }
    let(:entitlement_value) { create(:entitlement_value, organization:, entitlement:) }

    before do
      phase
      entitlement_value
      CatalogPlan.where(id: catalog_plan.id).update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    it "returns a not found plan failure and touches nothing" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("plan")
      expect(plan_rate_card.reload).not_to be_discarded
      expect(phase.reload).not_to be_discarded
      expect(entitlement.reload).not_to be_discarded
      expect(entitlement_value.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "with threads", transaction: false do
    let(:locked) { Queue.new }
    let(:release) { Queue.new }

    # Frees a lock holder left waiting by a failed expectation.
    after { release << ->(_) {} }

    def destroy(catalog_plan_id)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.call(catalog_plan: CatalogPlan.find(catalog_plan_id))
        end
      end
    end

    # Holds the plan row lock in another connection until `release` receives the block to run before the commit.
    def hold_plan_lock(catalog_plan_id)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.transaction do
            locked_plan = CatalogPlan.lock("FOR NO KEY UPDATE").find(catalog_plan_id)
            locked << true
            release.pop.call(locked_plan)
          end
        end
      end
    end

    it "answers not found to a destroy that waited on a lock held by a destroy" do
      holder = hold_plan_lock(catalog_plan.id)
      locked.pop

      destroyer = destroy(catalog_plan.id)
      expect(destroyer.join(0.5)).to be_nil

      release << ->(locked_plan) { locked_plan.discard! }
      holder.join
      destroyer_result = destroyer.value
      expect(destroyer_result).not_to be_success
      expect(destroyer_result.error).to be_a(BaseService::NotFoundFailure)
      expect(destroyer_result.error.resource).to eq("plan")
    end
  end

  context "when the plan is attached to contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "blocks the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(catalog_plan.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when the surrounding transaction rolls back" do
    before do
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "does not deliver either event channel", transaction: false do
      plan_rate_card

      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(kafka_messages).to be_empty
      expect(catalog_plan.reload).not_to be_discarded
      expect(plan_rate_card.reload).not_to be_discarded
    end
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
