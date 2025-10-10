# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::PaymentMethodsController, type: :request do
  describe "GET /api/v1/customers/:external_id/payment_methods" do
    subject { get_with_token(organization, "/api/v1/customers/#{external_id}/payment_methods", {}) }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:external_id) { customer.external_id }
    let(:payment_method) { create(:payment_method, customer:, organization:) }
    let(:second_payment_method) { create(:payment_method, organization:, customer:, is_default: false) }

    include_examples "requires API permission", "payment_method", "read"

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    context "with customer from another organization" do
      let(:customer) { create(:customer) }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    context "with payment methods" do
      before do
        payment_method
        second_payment_method
      end

      it "returns customer's payment methods" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payment_methods].count).to eq(2)
        expect(json[:payment_methods].map { |r| r[:lago_id] }).to contain_exactly(
          payment_method.id,
          second_payment_method.id
        )
      end
    end
  end
end
