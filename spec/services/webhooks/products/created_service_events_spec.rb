# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Products::CreatedService do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product_category) do
    create(
      :product_category,
      organization:,
      name: "Cloud services",
      code: "cloud_services",
      description: "Cloud product category",
      invoice_display_name: "Cloud"
    )
  end
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:product) do
    create(
      :product,
      organization:,
      product_category:,
      billable_metric:,
      name: "API access",
      code: "api_access",
      description: "API usage",
      invoice_display_name: "API",
      product_type: "metered"
    )
  end
  let(:product_filter) do
    create(:product_filter, organization:, product:, name: "Region", code: "region")
  end

  before { product_filter }

  describe Webhooks::Products::CreatedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it "creates a webhook with every serialized product field" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product.created",
        "object_type" => "product",
        "organization_id" => organization.id,
        "product" => {
          "lago_id" => product.id,
          "product_category_code" => "cloud_services",
          "billable_metric_code" => "api_calls",
          "name" => "API access",
          "code" => "api_access",
          "description" => "API usage",
          "invoice_display_name" => "API",
          "product_type" => "metered",
          "filters_count" => 1,
          "created_at" => product.created_at.iso8601,
          "updated_at" => product.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::Products::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it "creates a webhook with every serialized product field after an update" do
      product.update!(name: "Updated API access")

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product.updated",
        "object_type" => "product",
        "organization_id" => organization.id,
        "product" => {
          "lago_id" => product.id,
          "product_category_code" => "cloud_services",
          "billable_metric_code" => "api_calls",
          "name" => "Updated API access",
          "code" => "api_access",
          "description" => "API usage",
          "invoice_display_name" => "API",
          "product_type" => "metered",
          "filters_count" => 1,
          "created_at" => product.created_at.iso8601,
          "updated_at" => product.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::Products::DeletedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it "creates a webhook with every serialized product field after deletion" do
      product.discard
      product.reload

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product.deleted",
        "object_type" => "product",
        "organization_id" => organization.id,
        "product" => {
          "lago_id" => product.id,
          "product_category_code" => "cloud_services",
          "billable_metric_code" => "api_calls",
          "name" => "API access",
          "code" => "api_access",
          "description" => "API usage",
          "invoice_display_name" => "API",
          "product_type" => "metered",
          "filters_count" => 1,
          "created_at" => product.created_at.iso8601,
          "updated_at" => product.updated_at.iso8601,
          "deleted_at" => product.deleted_at.iso8601
        }
      )
    end
  end
end
