# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::IntegrationCustomersController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:external_id) { customer.external_id }

  let(:netsuite_customer) do
    create(:netsuite_customer, customer:, organization:, category: "accounting", code: "netsuite_eu", is_default: true)
  end
  let(:xero_customer) do
    create(:xero_customer, customer:, organization:, category: "accounting", code: "xero_eu", is_default: false)
  end

  before do
    netsuite_customer
    xero_customer
  end

  describe "PUT /api/v1/customers/:external_id/integration_customers/:code/set_as_default" do
    subject do
      put_with_token(organization, "/api/v1/customers/#{external_id}/integration_customers/#{code}/set_as_default")
    end

    let(:code) { "xero_eu" }

    include_examples "requires API permission", "customer", "write"

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end

    context "with unknown integration connection" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("integration_customer_not_found")
      end
    end

    context "with a valid connection" do
      it "sets the connection as default and clears the same-category sibling" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:integration_customer][:lago_id]).to eq(xero_customer.id)
        expect(json[:integration_customer][:is_default]).to be(true)
        expect(xero_customer.reload.is_default).to be(true)
        expect(netsuite_customer.reload.is_default).to be(false)
      end
    end

    context "when the advisory lock cannot be acquired" do
      before do
        allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "returns an unprocessable entity error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("lock_acquisition_failed")
        expect(xero_customer.reload.is_default).to be(false)
      end
    end
  end
end
