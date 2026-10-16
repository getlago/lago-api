# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Coupons::DeletedService do
  subject(:webhook_service) { described_class.new(object: coupon) }

  let(:organization) { create(:organization) }
  let(:coupon) do
    create(
      :coupon,
      organization:,
      name: "Spring sale",
      code: "spring_sale",
      description: "10% off for 3 months",
      coupon_type: "percentage",
      amount_cents: nil,
      amount_currency: nil,
      percentage_rate: 10.5,
      frequency: "recurring",
      frequency_duration: 3,
      reusable: false,
      limited_plans: true,
      limited_billable_metrics: true,
      expiration: "time_limit",
      expiration_at: Time.zone.parse("2026-12-31T23:59:59Z")
    )
  end
  let(:plan) { create(:plan, organization:, code: "premium") }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }

  before do
    create(:coupon_plan, coupon:, plan:)
    create(:coupon_billable_metric, coupon:, billable_metric:)
  end

  describe ".call" do
    it "creates a webhook with every serialized coupon field" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "coupon.deleted",
        "object_type" => "coupon",
        "organization_id" => organization.id,
        "coupon" => {
          "lago_id" => coupon.id,
          "name" => "Spring sale",
          "code" => "spring_sale",
          "description" => "10% off for 3 months",
          "coupon_type" => "percentage",
          "amount_cents" => nil,
          "amount_currency" => nil,
          "percentage_rate" => "10.5",
          "frequency" => "recurring",
          "frequency_duration" => 3,
          "reusable" => false,
          "limited_plans" => true,
          "limited_billable_metrics" => true,
          "plan_codes" => ["premium"],
          "billable_metric_codes" => ["api_calls"],
          "created_at" => coupon.created_at.iso8601,
          "expiration" => "time_limit",
          "expiration_at" => "2026-12-31T23:59:59Z",
          "terminated_at" => nil
        }
      )
    end
  end
end
