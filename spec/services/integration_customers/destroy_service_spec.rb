# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::DestroyService do
  subject(:destroy_service) { described_class.new(integration_customer:) }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization:) }

  describe "#call" do
    before { integration_customer }

    context "when integration customer is present" do
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

      it "destroys the integration customer" do
        expect { destroy_service.call }
          .to change(IntegrationCustomers::BaseCustomer, :count).by(-1)
      end

      it "returns the integration customer" do
        result = destroy_service.call

        expect(result).to be_success
        expect(result.integration_customer).to eq(integration_customer)
      end
    end

    context "when integration customer is not found" do
      let(:integration_customer) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_customer_not_found")
      end
    end
  end
end
