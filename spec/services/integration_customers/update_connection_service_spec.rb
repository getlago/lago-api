# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::UpdateConnectionService do
  subject(:update_service) { described_class.new(integration_customer:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:, code: "old_code") }
  let(:params) { {} }

  describe "#call" do
    subject(:result) { update_service.call }

    context "when integration customer is not found" do
      let(:integration_customer) { nil }
      let(:params) { {code: "new_code"} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_customer_not_found")
      end
    end

    context "when only the code is updated" do
      let(:params) { {code: "new_code"} }

      it "updates the code" do
        expect { update_service.call }
          .to change { integration_customer.reload.code }.from("old_code").to("new_code")
      end

      it "returns the integration customer" do
        expect(result).to be_success
        expect(result.integration_customer).to eq(integration_customer)
      end

      it "enqueues the update job" do
        expect { update_service.call }.to have_enqueued_job(IntegrationCustomers::UpdateJob).with(
          integration_customer_params: {
            integration_type: "netsuite",
            integration_code: integration.code
          },
          integration:,
          integration_customer:
        )
      end
    end

    context "when the external customer id is updated" do
      let(:params) { {code: "new_code", external_customer_id: "external-123"} }

      it "updates the code" do
        expect { update_service.call }
          .to change { integration_customer.reload.code }.from("old_code").to("new_code")
      end

      it "enqueues the update job with the integration customer params" do
        expect { update_service.call }.to have_enqueued_job(IntegrationCustomers::UpdateJob).with(
          integration_customer_params: {
            external_customer_id: "external-123",
            integration_type: "netsuite",
            integration_code: integration.code
          },
          integration:,
          integration_customer:
        )
      end
    end

    context "when the subsidiary id and the sync with provider flag are updated" do
      let(:params) { {subsidiary_id: "sub-1", sync_with_provider: true} }

      it "enqueues the update job with the integration customer params" do
        expect { update_service.call }.to have_enqueued_job(IntegrationCustomers::UpdateJob).with(
          integration_customer_params: {
            subsidiary_id: "sub-1",
            sync_with_provider: true,
            integration_type: "netsuite",
            integration_code: integration.code
          },
          integration:,
          integration_customer:
        )
      end
    end

    context "with a hubspot connection" do
      let(:integration) { create(:hubspot_integration, organization:) }
      let(:integration_customer) { create(:hubspot_customer, integration:, customer:, code: "old_code") }
      let(:params) { {targeted_object: "companies"} }

      it "enqueues the update job with the integration customer params" do
        expect { update_service.call }.to have_enqueued_job(IntegrationCustomers::UpdateJob).with(
          integration_customer_params: {
            targeted_object: "companies",
            integration_type: "hubspot",
            integration_code: integration.code
          },
          integration:,
          integration_customer:
        )
      end
    end

    context "with a salesforce connection" do
      let(:integration) { create(:salesforce_integration, organization:) }
      let(:integration_customer) { create(:salesforce_customer, integration:, customer:, code: "old_code") }
      let(:params) { {code: "new_code", external_customer_id: "external-123"} }

      it "updates the code" do
        expect { update_service.call }
          .to change { integration_customer.reload.code }.from("old_code").to("new_code")
      end

      it "does not enqueue the update job" do
        expect { update_service.call }.not_to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end

    context "with an anrok connection" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:, code: "old_code") }
      let(:params) { {code: "new_code", external_customer_id: "external-123"} }

      it "updates the code" do
        expect { update_service.call }
          .to change { integration_customer.reload.code }.from("old_code").to("new_code")
      end

      it "does not enqueue the update job" do
        expect { update_service.call }.not_to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end

    context "when the customer is a partner account" do
      let_it_be(:customer) { create(:customer, organization:, account_type: "partner") }
      let(:params) { {code: "new_code", external_customer_id: "external-123"} }

      it "updates the code" do
        expect { update_service.call }
          .to change { integration_customer.reload.code }.from("old_code").to("new_code")
      end

      it "does not enqueue the update job" do
        expect { update_service.call }.not_to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end
  end
end
