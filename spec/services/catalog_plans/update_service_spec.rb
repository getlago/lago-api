# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::UpdateService do
  subject(:result) { described_class.call(catalog_plan:, params:) }

  let(:catalog_plan) { create(:catalog_plan, name: "Before", code: "before") }
  let(:params) { {name: "After", code: "after"} }

  it "updates the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan.reload).to have_attributes(name: "After", code: "after")
  end

  it "enqueues a plan.updated webhook" do
    result

    expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", catalog_plan)
  end

  context "when send_webhook is false" do
    it "does not enqueue the webhook but still produces the activity log" do
      described_class.call(catalog_plan:, params:, send_webhook: false)

      expect(SendWebhookJob).not_to have_been_enqueued.with("plan.updated", catalog_plan)
      expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(catalog_plan)
    end
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the update is invalid" do
    let(:params) { {currency: "INVALID"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end

    it "emits no webhook and no activity log" do
      result

      expect(SendWebhookJob).not_to have_been_enqueued
      expect(Utils::ActivityLog).not_to have_produced("plan.updated")
    end
  end

  context "when changing the currency of a plan holding wallet templates" do
    let(:catalog_plan) { create(:catalog_plan, currency: "EUR") }
    let(:params) { {currency: "USD"} }

    before { create(:plan_wallet, organization: catalog_plan.organization, catalog_plan:) }

    it "rejects the change" do
      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["not_editable_with_wallets"])
    end
  end

  context "when changing the currency of a plan holding applied rate cards" do
    let(:catalog_plan) { create(:catalog_plan, currency: "EUR") }
    let(:params) { {currency: "USD"} }

    before { create(:plan_rate_card, organization: catalog_plan.organization, catalog_plan:) }

    it "rejects the change" do
      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["not_editable_with_applied_rate_cards"])
    end

    it "still allows editing other attributes" do
      result = described_class.call(catalog_plan:, params: {name: "Renamed"})

      expect(result).to be_success
      expect(result.catalog_plan.reload.name).to eq("Renamed")
    end
  end

  context "when changing the currency of a plan attached to a contract" do
    let(:catalog_plan) { create(:catalog_plan, currency: "EUR") }
    let(:params) { {currency: "USD"} }

    before do
      customer = create(:customer, organization: catalog_plan.organization)
      create(:contract, organization: catalog_plan.organization, customer:, catalog_plan:)
    end

    it "rejects it as plan_locked, even without plan-level rate cards" do
      expect(catalog_plan.applied_rate_cards).to be_empty
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
    end
  end

  context "when the plan is attached to a contract" do
    let(:catalog_plan) { create(:catalog_plan, name: "Growth", code: "growth", description: "Old") }

    before do
      customer = create(:customer, organization: catalog_plan.organization)
      create(:contract, organization: catalog_plan.organization, customer:, catalog_plan:)
    end

    it "rejects a code change" do
      result = described_class.call(catalog_plan:, params: {code: "growth-v2"})

      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(catalog_plan.reload.code).to eq("growth")
    end

    it "still allows editing the name, description and invoice display name" do
      result = described_class.call(catalog_plan:, params: {name: "Renamed", description: "New", invoice_display_name: "On Invoice"})

      expect(result).to be_success
      expect(catalog_plan.reload).to have_attributes(name: "Renamed", description: "New", invoice_display_name: "On Invoice")
    end

    it "accepts the unchanged code passed back with an editable field" do
      result = described_class.call(catalog_plan:, params: {code: "growth", name: "Renamed"})

      expect(result).to be_success
      expect(catalog_plan.reload.name).to eq("Renamed")
    end
  end

  describe "taxes" do
    let(:organization) { catalog_plan.organization }
    let(:tax1) { create(:tax, organization:) }
    let(:tax2) { create(:tax, organization:) }
    let(:params) { {tax_codes: [tax2.code]} }

    before { create(:plan_applied_tax, :catalog_plan, catalog_plan:, tax: tax1, organization:) }

    it "replaces the catalog plan taxes" do
      expect(result).to be_success
      expect(result.catalog_plan.taxes).to eq([tax2])
    end

    context "when tax codes are empty" do
      let(:params) { {tax_codes: []} }

      it "removes all catalog plan taxes" do
        expect(result).to be_success
        expect(result.catalog_plan.taxes).to be_empty
      end
    end

    context "when tax codes are null" do
      let(:params) { {tax_codes: nil} }

      it "keeps the existing taxes" do
        expect(result).to be_success
        expect(result.catalog_plan.taxes).to eq([tax1])
      end
    end

    context "when tax codes are omitted" do
      let(:params) { {name: "Renamed"} }

      it "keeps the existing taxes" do
        expect(result).to be_success
        expect(result.catalog_plan.taxes).to eq([tax1])
      end
    end

    context "when the catalog plan is attached to a contract" do
      before do
        customer = create(:customer, organization:)
        create(:contract, organization:, customer:, catalog_plan:)
      end

      it "still updates the taxes" do
        expect(result).to be_success
        expect(result.catalog_plan.taxes).to eq([tax2])
      end
    end

    context "when a tax belongs to another organization" do
      let(:other_tax) { create(:tax) }
      let(:params) { {name: "Should roll back", tax_codes: [other_tax.code]} }

      it "returns a tax not found failure and rolls back other changes" do
        expect(result).to be_a(described_class::Result)
        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
        expect(catalog_plan.reload.name).to eq("Before")
        expect(catalog_plan.taxes).to eq([tax1])
      end
    end
  end

  describe "metadata" do
    let(:organization) { catalog_plan.organization }

    before { create(:item_metadata, owner: catalog_plan, organization:, value: {"crm_id" => "123"}) }

    context "with new metadata" do
      let(:params) { {metadata: {tier: "silver"}} }

      it "replaces it with string keys" do
        expect(result).to be_success
        expect(catalog_plan.reload.metadata.value).to eq("tier" => "silver")
      end
    end

    context "when metadata is omitted" do
      let(:params) { {name: "Renamed"} }

      it "keeps it" do
        expect(result).to be_success
        expect(catalog_plan.reload.metadata.value).to eq("crm_id" => "123")
      end
    end

    context "with empty metadata" do
      let(:params) { {metadata: {}} }

      it "stores an empty object" do
        expect(result).to be_success
        expect(catalog_plan.reload.metadata.value).to eq({})
      end
    end

    context "with null metadata" do
      let(:params) { {metadata: nil} }

      it "removes it" do
        expect(result).to be_success
        expect(catalog_plan.reload.metadata).to be_nil
      end
    end

    [{"crm_id" => "123"}, {"tier" => "silver"}].each do |metadata|
      context "with only metadata #{metadata}" do
        let(:params) { {metadata:} }

        before { catalog_plan.update!(updated_at: 1.day.ago) }

        it "moves updated_at and enqueues one plan.updated" do
          expect { result }.to change { catalog_plan.reload.updated_at }

          expect(SendWebhookJob).to have_been_enqueued.once
          expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", catalog_plan)
        end
      end
    end

    context "with metadata that is not an object" do
      let(:params) { {name: "After", metadata: "abc"} }

      it "refuses it on metadata and changes nothing" do
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(metadata: ["value_is_invalid"])
        expect(catalog_plan.reload.name).to eq("Before")
        expect(catalog_plan.metadata.value).to eq("crm_id" => "123")
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "with invalid metadata content next to a name" do
      let(:params) { {name: "After", metadata: {a: 1}} }

      it "refuses it on metadata and rolls back the name" do
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(metadata: ["value_is_invalid"])
        expect(catalog_plan.reload.name).to eq("Before")
        expect(catalog_plan.metadata.value).to eq("crm_id" => "123")
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when the plan is attached to a contract" do
      before do
        customer = create(:customer, organization:)
        create(:contract, organization:, customer:, catalog_plan:)
      end

      it "still replaces the metadata" do
        result = described_class.call(catalog_plan:, params: {metadata: {tier: "silver"}})

        expect(result).to be_success
        expect(catalog_plan.reload.metadata.value).to eq("tier" => "silver")
      end

      it "refuses a currency change as plan_locked and keeps the metadata" do
        result = described_class.call(catalog_plan:, params: {currency: "USD", metadata: {tier: "silver"}})

        expect(result.error.messages).to eq(plan: ["plan_locked"])
        expect(catalog_plan.reload.metadata.value).to eq("crm_id" => "123")
      end
    end

    context "when the plan is deleted after it was loaded" do
      let(:params) { {metadata: {tier: "silver"}} }

      before { CatalogPlan.find(catalog_plan.id).discard! }

      it "returns a plan not found failure and writes nothing" do
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("plan")
        expect(Metadata::ItemMetadata.find_by(owner: catalog_plan).value).to eq("crm_id" => "123")
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when logging the change", :capture_kafka_messages, transaction: false do
      before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

      context "with a metadata-only change" do
        let(:params) { {metadata: {tier: "silver"}} }

        it "logs the metadata diff" do
          expect(result).to be_success

          expect(kafka_messages.size).to eq(1)
          payload = JSON.parse(kafka_messages.first.fetch(:payload))
          expect(payload).to include("activity_type" => "plan.updated", "resource_id" => catalog_plan.id)
          expect(payload.fetch("activity_object_changes")).to eq("metadata" => [{"crm_id" => "123"}, {"tier" => "silver"}])
        end
      end

      context "with invalid metadata content next to a name" do
        let(:params) { {name: "After", metadata: {a: 1}} }

        it "logs nothing" do
          expect(result).to be_failure
          expect(kafka_messages).to be_empty
        end
      end
    end
  end

  context "when two requests write the first metadata at once", transaction: false do
    it "applies them one after the other" do
      catalog_plan_id = catalog_plan.id

      # The first call pauses after its metadata write, holding its transaction open, so the second one
      # starts while the first metadata row is not committed yet.
      first_call = Queue.new
      first_call << true
      written = Queue.new
      resume = Queue.new

      allow(Metadata::UpdateItemService).to receive(:call).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap do
          if first_call.pop(timeout: 0)
            written << true
            resume.pop(timeout: 10)
          end
        end
      end

      update = lambda do |metadata|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(catalog_plan: CatalogPlan.find(catalog_plan_id), params: {metadata:})
          end
        end
      end

      first = update.call({tier: "gold"})
      expect(written.pop(timeout: 10)).to be(true)
      second = update.call({tier: "silver"})
      sleep 0.5
      resume << true

      expect([first.value, second.value]).to all(be_success)
      expect(catalog_plan.reload.metadata.value).to eq("tier" => "silver")
    end
  end

  context "when a concurrent request takes the new code" do
    before do
      create(:catalog_plan, organization: catalog_plan.organization, code: "after")
      # The uniqueness validation ran before the concurrent request committed.
      allow_any_instance_of(ActiveRecord::Validations::UniquenessValidator).to receive(:validate_each) # rubocop:disable RSpec/AnyInstance
    end

    it "returns the validation error of a taken value" do
      expect(result.error.messages).to eq(code: ["value_already_exist"])
    end
  end
end
