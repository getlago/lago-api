# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrderFormsController do
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, quote:, organization:) }
  let(:order_form) { create(:order_form, organization:, customer:, quote_version:) }

  describe "GET /api/v1/order_forms" do
    subject { get_with_token(organization, "/api/v1/order_forms") }

    let!(:order_form) { create(:order_form, organization:, customer:, quote_version:) }

    before { create(:order_form, :signed, organization:, customer:) }

    include_examples "requires API permission", "order_form", "read"

    it "returns a list of order forms" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_forms].count).to eq(2)
    end

    context "when filtering by status" do
      subject { get_with_token(organization, "/api/v1/order_forms", {status: "generated"}) }

      it "returns only matching order forms" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_forms].count).to eq(1)
        expect(json[:order_forms].first[:lago_id]).to eq(order_form.id)
      end
    end

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_not_available")
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

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_not_available")
      end
    end
  end

  describe "POST /api/v1/order_forms/:id/mark_as_signed", :premium do
    subject do
      post_with_token(
        organization,
        "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
        {}
      )
    end

    before { order_form }

    include_examples "requires API permission", "order_form", "write"

    it "marks the order form as signed" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_form][:lago_id]).to eq(order_form.id)
      expect(json[:order_form][:status]).to eq("signed")
    end

    context "when order form is not signable" do
      let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }

      it "returns an error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context "when order form does not exist" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{SecureRandom.uuid}/mark_as_signed",
          {}
        )
      end

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order_form")
      end
    end
  end
end
