# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ProductCategories::CreatedService do
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
      code: "api_access"
    )
  end

  before { product }

  describe Webhooks::ProductCategories::CreatedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it "creates a webhook with every serialized product category field" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_category.created",
        "object_type" => "product_category",
        "organization_id" => organization.id,
        "product_category" => {
          "lago_id" => product_category.id,
          "name" => "Cloud services",
          "code" => "cloud_services",
          "description" => "Cloud product category",
          "invoice_display_name" => "Cloud",
          "products_count" => 1,
          "created_at" => product_category.created_at.iso8601,
          "updated_at" => product_category.updated_at.iso8601
        }
      )
    end
  end

  describe Webhooks::ProductCategories::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it "creates a webhook with every serialized product category field after an update" do
      product_category.update!(name: "Updated cloud services")

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_category.updated",
        "object_type" => "product_category",
        "organization_id" => organization.id,
        "product_category" => {
          "lago_id" => product_category.id,
          "name" => "Updated cloud services",
          "code" => "cloud_services",
          "description" => "Cloud product category",
          "invoice_display_name" => "Cloud",
          "products_count" => 1,
          "created_at" => product_category.created_at.iso8601,
          "updated_at" => product_category.updated_at.iso8601
        }
      )
    end
  end

  describe Webhooks::ProductCategories::DeletedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it "creates a webhook with every serialized product category field after deletion" do
      product_category.discard
      product_category.reload

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_category.deleted",
        "object_type" => "product_category",
        "organization_id" => organization.id,
        "product_category" => {
          "lago_id" => product_category.id,
          "name" => "Cloud services",
          "code" => "cloud_services",
          "description" => "Cloud product category",
          "invoice_display_name" => "Cloud",
          "products_count" => 1,
          "created_at" => product_category.created_at.iso8601,
          "updated_at" => product_category.updated_at.iso8601
        }
      )
    end
  end
end
