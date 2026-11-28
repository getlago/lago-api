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
    expect(webhook.payload.fetch("product")).not_to have_key("filters_count")
    expect(webhook.payload.fetch("product")).not_to have_key("filters")
    expect(webhook.payload.fetch("product")).not_to have_key("rate_cards")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "product.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object")).not_to have_key("filters")
    expect(activity.fetch("activity_object")).not_to have_key("rate_cards")
  end

  context "when the product has contract alerts" do
    let(:product_alert) { create(:contract_usage_units_alert, organization:, product:, updated_at: 1.day.ago) }
    let(:filter_alert) { create(:contract_usage_amount_alert, organization:, product:, product_filter: product.filters.first, updated_at: 1.day.ago) }
    let(:other_product_alert) { create(:contract_usage_units_alert, organization:, product: create(:product, organization:)) }
    let(:whole_contract_alert) { create(:contract_usage_amount_alert, organization:) }
    let(:triggered_alert) { create(:contract_triggered_alert, alert: product_alert) }

    before do
      freeze_time
      product_alert
      filter_alert
      other_product_alert
      whole_contract_alert
      triggered_alert
    end

    it "discards the alerts of the product and of its filters, and deletes their thresholds" do
      expect(result).to be_success
      expect(product_alert.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
      expect(filter_alert.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
      expect(UsageMonitoring::ContractAlertThreshold.where(contract_alert_id: [product_alert.id, filter_alert.id])).to be_empty
    end

    it "keeps the alerts of other products and of the whole contract, and the triggered history" do
      expect(result).to be_success
      expect(other_product_alert.reload).not_to be_discarded
      expect(whole_contract_alert.reload).not_to be_discarded
      expect(other_product_alert.thresholds.count).to eq(1)
      expect(whole_contract_alert.thresholds.count).to eq(1)
      expect(UsageMonitoring::ContractTriggeredAlert.where(id: triggered_alert.id)).to exist
    end
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
    let(:alert) { create(:contract_usage_units_alert, organization:, product:) }

    before do
      rate_card = create(:rate_card, organization:, product:)
      create(:contract_rate_card, organization:, rate_card:)
      alert
    end

    it "returns a validation failure and discards nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:product]).to eq(["attached_to_plan_or_subscription"])
      expect(product.reload).not_to be_discarded
      expect(alert.reload).not_to be_discarded
      expect(alert.thresholds.count).to eq(1)
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
