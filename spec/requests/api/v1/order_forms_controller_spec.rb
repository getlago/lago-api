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
      subject { get_with_token(organization, "/api/v1/order_forms", {status: "generated"}) }

      it "returns only matching order forms" do
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

  describe "POST /api/v1/order_forms/:id/mark_as_signed" do
    subject do
      post_with_token(
        organization,
        "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
        {order_form: {signed_by_user_id: membership.user_id}}
      )
    end

    let(:membership) { create(:membership, organization:) }

    before { order_form }

    include_examples "requires API permission", "order_form", "write"

    it "marks the order form as signed" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_form][:lago_id]).to eq(order_form.id)
      expect(json[:order_form][:status]).to eq("signed")
      expect(json[:order_form][:signed_by_user_id]).to eq(membership.user_id)
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
          {order_form: {signed_by_user_id: membership.user_id}}
        )
      end

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order_form")
      end
    end

    context "when signed_by_user_id is invalid" do
      subject do
        post_with_token(
          organization,
          "/api/v1/order_forms/#{order_form.id}/mark_as_signed",
          {order_form: {signed_by_user_id: SecureRandom.uuid}}
        )
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:signed_by_user_id)
      end
    end
  end

  describe "POST /api/v1/order_forms/:id/void" do
    subject { post_with_token(organization, "/api/v1/order_forms/#{order_form.id}/void") }

    before { order_form }

    include_examples "requires API permission", "order_form", "write"

    it "voids the order form" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order_form][:lago_id]).to eq(order_form.id)
      expect(json[:order_form][:status]).to eq("voided")
    end

    context "when order form is not voidable" do
      let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }

      it "returns an error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context "when order form does not exist" do
      subject { post_with_token(organization, "/api/v1/order_forms/#{SecureRandom.uuid}/void") }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order_form")
      end
    end
  end
end
