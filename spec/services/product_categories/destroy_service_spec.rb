# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategories::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(product_category:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product_category) { create(:product_category, organization:) }
  let(:product) { create(:product, organization:, product_category:) }
  let(:fixed_product) { create(:product, :fixed, organization:, product_category:) }
  let(:product_filter) { create(:product_filter, organization:, product:) }
  let(:filter_value) { create(:product_filter_value, organization:, product_filter:) }
  let(:rate_card) { create(:rate_card, organization:, product:, product_filter:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:) }

  before do
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    next if product_category.nil?

    fixed_product
    filter_value
    rate
  end

  it "soft deletes the product_category and its items" do
    item_ids = product_category.products.ids

    expect(result).to be_success
    expect(product_category.reload).to be_discarded
    expect(Product.with_discarded.where(id: item_ids).map(&:discarded?)).to all(be(true))
  end

  it "publishes the legacy category event and activity arguments without child events" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("product_category.deleted", product_category)
    expect(Utils::ActivityLog).to have_received(:produce).with(product_category, "product_category.deleted", after_commit: true)
    expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "product.deleted", any_args)
  end

  it "delivers legacy serialization after deleting the hierarchy", transaction: false do
    create(:webhook_endpoint, organization:)
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    perform_enqueued_jobs(only: SendWebhookJob) { result }

    webhook = Webhook.find_by!(webhook_type: "product_category.deleted")
    expect(webhook.payload.fetch("product_category").fetch("products_count")).to eq(0)
    expect(webhook.payload.fetch("product_category")).not_to have_key("products")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "product_category.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object")).not_to have_key("products")
  end

  context "when the catalog flag is disabled" do
    let(:organization) { create(:organization) }

    it "publishes only the category event" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("product_category.deleted", product_category, any_args)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(product_category, "product_category.deleted", after_commit: true)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "product.deleted", any_args)
    end
  end

  context "when the surrounding transaction rolls back" do
    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "restores the category hierarchy and suppresses both event channels", transaction: false do
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(product_category.reload).not_to be_discarded
      expect(product_category.products.with_discarded.map(&:discarded?)).to all(be(false))
      expect(kafka_messages).to be_empty
    end
  end

  context "when product_category is nil" do
    let(:product_category) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
    end
  end

  context "when one of the product_category's items is priced on a plan" do
    before do
      item = create(:product, organization:, product_category:)
      rate_card = create(:rate_card, organization:, product: item)
      create(:plan_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:product_category]).to eq(["attached_to_plan_or_subscription"])
      expect(product_category.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end
end
