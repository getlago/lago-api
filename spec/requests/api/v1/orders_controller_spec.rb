# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrdersController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }
  let(:order) { create(:order, organization:, customer:, order_form:) }

  describe "GET /api/v1/orders" do
    subject { get_with_token(organization, "/api/v1/orders") }

    let(:order_form_two) { create(:order_form, :signed, organization:, customer:, quote:) }
    let!(:order) { create(:order, organization:, customer:, order_form:) }
    let!(:order_two) { create(:order, organization:, customer:, order_form: order_form_two, order_type: :one_off) }

    include_examples "requires API permission", "order", "read"

    it "returns a list of orders" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:orders].count).to eq(2)
    end

    context "when filtering by status" do
      subject { get_with_token(organization, "/api/v1/orders", {status: "created"}) }

      it "returns only matching orders" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:orders].count).to eq(2)
      end
    end

    context "when filtering by order_type" do
      subject { get_with_token(organization, "/api/v1/orders", {order_type: "one_off"}) }

      it "returns only matching orders" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:orders].count).to eq(1)
        expect(json[:orders].first[:lago_id]).to eq(order_two.id)
      end
    end
  end

  describe "GET /api/v1/orders/:id" do
    subject { get_with_token(organization, "/api/v1/orders/#{order.id}") }

    before { order }

    include_examples "requires API permission", "order", "read"

    it "returns the order" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order][:lago_id]).to eq(order.id)
      expect(json[:order][:number]).to eq(order.number)
      expect(json[:order][:status]).to eq("created")
      expect(json[:order]).to have_key(:execution_record)
    end

    context "when order does not exist" do
      subject { get_with_token(organization, "/api/v1/orders/#{SecureRandom.uuid}") }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order")
      end
    end
  end
end
