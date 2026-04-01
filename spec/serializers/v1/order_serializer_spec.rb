# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::OrderSerializer do
  subject(:serializer) { described_class.new(order, root_name: "order") }

  let(:order) { create(:order) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["order"]).to include(
      "lago_id" => order.id,
      "number" => order.number,
      "status" => "created",
      "order_type" => "subscription_creation",
      "execution_mode" => nil,
      "backdated_billing" => nil,
      "billing_snapshot" => order.billing_snapshot,
      "currency" => "EUR",
      "executed_at" => nil,
      "lago_organization_id" => order.organization_id,
      "lago_customer_id" => order.customer_id,
      "lago_order_form_id" => order.order_form_id,
      "created_at" => order.created_at.iso8601,
      "updated_at" => order.updated_at.iso8601
    )
  end
end
