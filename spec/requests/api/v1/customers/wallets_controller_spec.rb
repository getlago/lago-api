# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::WalletsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:external_id) { customer.external_id }
  let(:subscription) { create(:subscription, customer:) }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }
  let(:section_1) { create(:invoice_custom_section, organization:, code: "section_code_1") }
  let(:payment_method) { create(:payment_method, organization:, customer:) }

  before { subscription }

  describe "POST /api/v1/customers/:external_id/wallets" do
    it_behaves_like "a wallet create endpoint" do
      subject do
        post_with_token(organization, "/api/v1/customers/#{external_id}/wallets", {wallet: create_params})
      end

      context "when params[:external_customer_id] is empty" do
        it "uses the route :customer_external_id to determine the customer" do
          create_params.delete(:external_customer_id)

          subject
          expect(json[:wallet][:external_customer_id]).to eq(external_id)
        end
      end

      context "when params[:external_customer_id] differs from the route :customer_external_id" do
        it "uses the route :customer_external_id to determine the customer" do
          create_params[:external_customer_id] = "external-customer-id"

          subject
          expect(json[:wallet][:external_customer_id]).to eq(external_id)
        end
      end
    end
  end

  describe "PUT /api/v1/customers/:external_id/wallets/:id" do
    it_behaves_like "a wallet update endpoint" do
      subject do
        put_with_token(
          organization,
          "/api/v1/customers/#{external_id}/wallets/#{id}",
          {wallet: update_params}
        )
      end

      let(:id) { wallet.code }
    end
  end

  describe "GET /api/v1/wcustomers/:external_id/allets/:id" do
    it_behaves_like "a wallet show endpoint" do
      subject { get_with_token(organization, "/api/v1/customers/#{external_id}/wallets/#{id}") }

      let(:id) { wallet.code }
    end
  end

  describe "DELETE /api/v1/customers/:external_id/wallets/:id" do
    it_behaves_like "a wallet terminate endpoint" do
      subject { delete_with_token(organization, "/api/v1/customers/#{external_id}/wallets/#{id}") }

      let(:id) { wallet.code }
    end
  end

  describe "GET /api/v1/customers/:external_id/wallets" do
    it_behaves_like "a wallet index endpoint" do
      subject do
        get_with_token(organization, "/api/v1/customers/#{external_id}/wallets", params)
      end

      context "when external_customer_id does not belong to the current organization" do
        let(:other_org_customer) { create(:customer) }
        let(:external_id) { other_org_customer.external_id }

        it "returns a not found error" do
          subject
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
