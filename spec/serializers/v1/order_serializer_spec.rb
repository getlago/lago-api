# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::OrderSerializer do
  subject(:serializer) { described_class.new(order, root_name: "order") }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, organization:, quote:, currency: "EUR") }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["order"]).to include(
      "lago_id" => order.id,
      "number" => order.number,
      "status" => "created",
      "order_type" => "subscription_creation",
      "execution_mode" => nil,
      "billing_snapshot" => order.billing_snapshot,
      "currency" => "EUR",
      "executed_at" => nil,
      "execution_record" => order.execution_record,
      "lago_organization_id" => order.organization_id,
      "lago_customer_id" => order.customer_id,
      "lago_order_form_id" => order.order_form_id,
      "created_at" => order.created_at.iso8601,
      "updated_at" => order.updated_at.iso8601
    )
  end

  context "when the order failed" do
    let(:order) { create(:order, :failed, organization:, customer:, order_form:) }

    it "serializes the execution record trace" do
      result = JSON.parse(serializer.to_json)

      expect(result["order"]["status"]).to eq("failed")
      expect(result["order"]["execution_record"]).to eq(
        "executed_at" => nil,
        "execution_mode" => "execute_in_lago",
        "invoice_id" => nil,
        "errors" => ["currencies_does_not_match"]
      )
    end
  end
end
