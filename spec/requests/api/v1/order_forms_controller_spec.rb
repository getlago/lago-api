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

    context "when a signed_document is provided" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {signed_document:}}
        )
      end

      let(:signed_document) do
        "data:application/pdf;base64,#{Base64.encode64(File.read(Rails.root.join("spec/fixtures/blank.pdf")))}"
      end

      it "marks the order form as signed and returns the document url" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_form][:status]).to eq("signed")
        expect(json[:order_form][:signed_document_url]).to be_present
      end
    end

    context "when the signed_document is not a PDF" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {signed_document: "data:text/plain;base64,#{Base64.encode64("not a pdf")}"}}
        )
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:signed_document)
      end
    end

    context "when execution_mode and execution_date are provided" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {execution_mode: "execute_in_lago", execution_date: "2026-06-15"}}
        )
      end

      it "marks the order form as signed" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order_form][:status]).to eq("signed")
      end
    end

    context "when execution_mode is invalid" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {execution_mode: "unknown"}}
        )
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:execution_mode)
      end
    end

    context "when execution_date is not a date" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {execution_date: "not-a-date"}}
        )
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:execution_date)
      end
    end
  end
end
