# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::WalletsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:external_id) { customer.external_id }

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
