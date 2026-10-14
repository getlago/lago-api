# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::UpdateService do
  subject(:result) { described_class.call(product:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product) { create(:product, organization:, name: "Before", code: "before") }

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product.name).to eq("After")
    expect(result.product.description).to eq("new")
    expect(result.product.invoice_display_name).to eq("Display")
  end

  describe "code and product_category editability" do
    let(:other_product_category) { create(:product_category, organization:) }
    let(:params) { {code: "after", product_category_id: other_product_category.id} }

    it "updates the code and product_category attachment when not in a plan or subscription" do
      expect(result).to be_success
      expect(result.product.code).to eq("after")
      expect(result.product.product_category).to eq(other_product_category)
    end

    it "returns a not found failure when the product_category does not exist" do
      result = described_class.call(product:, params: {product_category_id: "unknown"})
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
    end

    context "when the item is attached to a plan" do
      before do
        rate_card = create(:rate_card, organization:, product:)
        create(:plan_rate_card, organization:, rate_card:)
      end

      it "rejects the structural change" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
        expect(product.reload.code).to eq("before")
      end

      it "accepts unchanged structural fields alongside other updates" do
        update_result = described_class.call(product:, params: {code: "before", name: "renamed"})

        expect(update_result).to be_success
        expect(product.reload.name).to eq("renamed")
      end
    end
  end

  it "produces an activity log" do
    update_result = described_class.call(product:, params: {name: "After"})

    expect(update_result).to be_success
    expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.updated", after_commit: true)
  end

  it "enqueues a product.updated webhook" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("product.updated", product)
  end

  context "when the update does not change persisted attributes" do
    let(:params) { {name: "Before"} }

    it "publishes both event channels" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("product.updated", product)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.updated", after_commit: true)
    end
  end

  context "when the catalog flag is disabled" do
    let(:organization) { create(:organization) }

    it "updates and publishes the product event" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("product.updated", product)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.updated", after_commit: true)
    end
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when the update fails validation" do
    let(:params) { {name: ""} }

    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "delivers neither event channel", :capture_kafka_messages do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(kafka_messages).to be_empty
    end
  end

  context "when the surrounding transaction rolls back" do
    before do
      product
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "suppresses both event channels", :capture_kafka_messages, transaction: false do
      expect do
        ActiveRecord::Base.transaction do
          expect(result).to be_success
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(product.reload.name).to eq("Before")
      expect(kafka_messages).to be_empty
    end
  end

  context "when name is blank" do
    let(:params) { {name: ""} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:name]).to be_present
    end
  end
end
