# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(product:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product) { create(:product, :with_filters, organization:) }

  before do
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    next if product.nil?

    filter = product.filters.first
    create(
      :product_filter_value,
      organization:,
      product_filter: filter,
      billable_metric_filter: create(:billable_metric_filter, organization:, billable_metric: product.billable_metric, values: %w[us])
    )
    create(:rate_card_rate, organization:, rate_card: create(:rate_card, organization:, product:))
  end

  it "soft deletes the item with its filters, values, rate cards and rates" do
    expect(result).to be_success
    expect(product.reload).to be_discarded
    expect(ProductFilter.with_discarded.where(product_id: product.id).map(&:discarded?)).to all(be(true))
    expect(RateCard.with_discarded.where(product_id: product.id).map(&:discarded?)).to all(be(true))
    expect(
      RateCardRate.with_discarded
        .where(rate_card_id: RateCard.with_discarded.where(product_id: product.id).ids)
        .map(&:discarded?)
    ).to all(be(true))
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.deleted", after_commit: true)
  end

  it "publishes product.deleted on the discarded product without webhook options" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("product.deleted", product)
    expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.deleted", after_commit: true)
  end

  it "delivers legacy serialization after deleting filters and rate cards", transaction: false do
    create(:webhook_endpoint, organization:)
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    perform_enqueued_jobs(only: SendWebhookJob) { result }

    webhook = Webhook.find_by!(webhook_type: "product.deleted")
    expect(webhook.payload.fetch("product").fetch("filters_count")).to eq(0)
    expect(webhook.payload.fetch("product")).not_to have_key("filters")
    expect(webhook.payload.fetch("product")).not_to have_key("rate_cards")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "product.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object")).not_to have_key("filters")
    expect(activity.fetch("activity_object")).not_to have_key("rate_cards")
  end

  context "when the catalog flag is disabled" do
    let(:organization) { create(:organization) }

    it "deletes and publishes the product event" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("product.deleted", product, any_args)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(product, "product.deleted", after_commit: true)
    end
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when the item is attached to a subscription" do
    before do
      rate_card = create(:rate_card, organization:, product:)
      create(:contract_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:product]).to eq(["attached_to_plan_or_subscription"])
      expect(product.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when the surrounding transaction rolls back" do
    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "restores the product and suppresses both event channels", transaction: false do
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(product.reload).not_to be_discarded
      expect(kafka_messages).to be_empty
    end
  end
end
