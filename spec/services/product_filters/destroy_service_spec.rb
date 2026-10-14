# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFilters::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(product_filter:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product_filter) { create(:product_filter, :with_values, organization:) }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "soft deletes the filter and its values" do
    value_ids = product_filter.values.ids
    expect(result).to be_success
    expect(product_filter.reload).to be_discarded
    expect(ProductFilterValue.with_discarded.where(id: value_ids).map(&:discarded?)).to all(be(true))
  end

  it "produces an activity log with legacy arguments" do
    result
    expect(Utils::ActivityLog).to have_received(:produce).with(product_filter, "product_filter.deleted", after_commit: true)
  end

  it "publishes product_filter.deleted without webhook options" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("product_filter.deleted", product_filter)
    expect(Utils::ActivityLog).to have_received(:produce).with(product_filter, "product_filter.deleted", after_commit: true)
  end

  it "delivers legacy serialization after deleting values and scoped cards", transaction: false do
    create(:rate_card, organization:, product: product_filter.product, product_filter:)
    create(:webhook_endpoint, organization:)
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    perform_enqueued_jobs(only: SendWebhookJob) { result }

    webhook = Webhook.find_by!(webhook_type: "product_filter.deleted")
    expect(webhook.payload.fetch("product_filter").fetch("values")).to eq([])
    expect(webhook.payload.fetch("product_filter")).not_to have_key("rate_cards")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "product_filter.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object").fetch("values")).to eq([])
    expect(activity.fetch("activity_object")).not_to have_key("rate_cards")
  end

  context "when the catalog flag is disabled" do
    let(:organization) { create(:organization) }

    it "deletes and publishes the filter event" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("product_filter.deleted", product_filter, any_args)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(product_filter, "product_filter.deleted", after_commit: true)
    end
  end

  context "when a scoped rate card exists" do
    let(:product) { product_filter.product }
    let!(:scoped_card) { create(:rate_card, organization:, product:, product_filter:) }

    it "discards the scoped rate card alongside the filter" do
      expect(result).to be_success
      expect(scoped_card.reload).to be_discarded
    end
  end

  context "when the item is attached to a plan" do
    before do
      rate_card = create(:rate_card, organization:, product: product_filter.product)
      create(:plan_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:product_filter]).to eq(["attached_to_plan_or_subscription"])
      expect(product_filter.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when product_filter is nil" do
    let(:product_filter) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_filter")
    end
  end

  context "when the surrounding transaction rolls back" do
    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "restores the filter and suppresses both event channels", transaction: false do
      value_ids = product_filter.values.ids

      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(product_filter.reload).not_to be_discarded
      expect(ProductFilterValue.with_discarded.where(id: value_ids).map(&:discarded?)).to all(be(false))
      expect(kafka_messages).to be_empty
    end
  end
end
