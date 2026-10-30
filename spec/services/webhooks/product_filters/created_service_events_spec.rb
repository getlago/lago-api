# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ProductFilters::CreatedService do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product_category) do
    create(:product_category, organization:, name: "Cloud services", code: "cloud_services")
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
  let(:product_filter) do
    create(
      :product_filter,
      organization:,
      product:,
      name: "Region",
      code: "region",
      description: "Customer region",
      invoice_display_name: "Region"
    )
  end
  let(:billable_metric_filter) do
    create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: ["eu"])
  end
  let(:filter_value) do
    create(
      :product_filter_value,
      organization:,
      product_filter:,
      billable_metric_filter:,
      value: "eu"
    )
  end

  describe Webhooks::ProductFilters::CreatedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it "creates a webhook with every serialized product filter field" do
      filter_value

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_filter.created",
        "object_type" => "product_filter",
        "organization_id" => organization.id,
        "product_filter" => {
          "lago_id" => product_filter.id,
          "product_code" => "api_access",
          "product_category_code" => "cloud_services",
          "name" => "Region",
          "code" => "region",
          "description" => "Customer region",
          "invoice_display_name" => "Region",
          "values" => [{"key" => "region", "value" => "eu"}],
          "created_at" => product_filter.created_at.iso8601,
          "updated_at" => product_filter.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::ProductFilters::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it "creates a webhook with every serialized product filter field after an update" do
      filter_value
      product_filter.update!(name: "Updated region")

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_filter.updated",
        "object_type" => "product_filter",
        "organization_id" => organization.id,
        "product_filter" => {
          "lago_id" => product_filter.id,
          "product_code" => "api_access",
          "product_category_code" => "cloud_services",
          "name" => "Updated region",
          "code" => "region",
          "description" => "Customer region",
          "invoice_display_name" => "Region",
          "values" => [{"key" => "region", "value" => "eu"}],
          "created_at" => product_filter.created_at.iso8601,
          "updated_at" => product_filter.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::ProductFilters::DeletedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it "creates a webhook with every serialized product filter field after deletion" do
      filter_value
      product_filter.discard
      product_filter.reload

      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "product_filter.deleted",
        "object_type" => "product_filter",
        "organization_id" => organization.id,
        "product_filter" => {
          "lago_id" => product_filter.id,
          "product_code" => "api_access",
          "product_category_code" => "cloud_services",
          "name" => "Region",
          "code" => "region",
          "description" => "Customer region",
          "invoice_display_name" => "Region",
          "values" => [],
          "created_at" => product_filter.created_at.iso8601,
          "updated_at" => product_filter.updated_at.iso8601,
          "deleted_at" => product_filter.deleted_at.iso8601
        }
      )
    end
  end
end
