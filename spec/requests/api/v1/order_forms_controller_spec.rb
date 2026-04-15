# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrderFormsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, organization:, customer:, quote:) }

  describe "GET /api/v1/order_forms" do
    subject { get_with_token(organization, "/api/v1/order_forms") }

    let!(:order_form) { create(:order_form, organization:, customer:, quote:) }

    before { create(:order_form, :signed, organization:, customer:, quote:) }

    include_examples "requires API permission", "order_form", "read"

    it "returns a list of order forms" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_forms].count).to eq(2)
    end

    context "when filtering by status" do
      subject { get_with_token(organization, "/api/v1/order_forms", {status: ["generated"]}) }

      it "returns only matching order forms" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_forms].count).to eq(1)
        expect(json[:order_forms].first[:lago_id]).to eq(order_form.id)
      end
    end

    context "when filtering by number" do
      subject { get_with_token(organization, "/api/v1/order_forms", {number: [order_form.number]}) }

      it "returns only matching order forms" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_forms].count).to eq(1)
        expect(json[:order_forms].first[:lago_id]).to eq(order_form.id)
      end
    end

    context "when filtering by customer_id" do
      subject { get_with_token(organization, "/api/v1/order_forms", {customer_id: [customer.id]}) }

      let(:other_customer) { create(:customer, organization:) }
      let(:other_quote) { create(:quote, organization:, customer: other_customer) }

      before { create(:order_form, organization:, customer: other_customer, quote: other_quote) }

      it "returns only matching order forms" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_forms].count).to eq(2)
      end
    end

    context "when filtering by order_form_date_from and order_form_date_to" do
      subject do
        get_with_token(organization, "/api/v1/order_forms", {
          order_form_date_from: 4.days.ago.iso8601,
          order_form_date_to: 2.days.ago.iso8601
        })
      end

      let!(:order_form) { create(:order_form, organization:, customer:, quote:, created_at: 3.days.ago) }

      before { create(:order_form, :signed, organization:, customer:, quote:, created_at: 1.day.ago) }

      it "returns only order forms within the date range" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_forms].count).to eq(1)
        expect(json[:order_forms].first[:lago_id]).to eq(order_form.id)
      end
    end
  end

  describe "GET /api/v1/order_forms/:id" do
    subject { get_with_token(organization, "/api/v1/order_forms/#{order_form.id}") }

    before { order_form }

    include_examples "requires API permission", "order_form", "read"

    it "returns the order form" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_form][:lago_id]).to eq(order_form.id)
      expect(json[:order_form][:number]).to eq(order_form.number)
      expect(json[:order_form][:status]).to eq("generated")
    end

    context "when order form does not exist" do
      subject { get_with_token(organization, "/api/v1/order_forms/#{SecureRandom.uuid}") }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order_form")
      end
    end
  end
end
