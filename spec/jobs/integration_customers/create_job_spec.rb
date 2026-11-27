# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::CreateJob do
  before_all do
    create_default(:organization)
  end

  let(:integration) { create(:netsuite_integration) }
  let(:integration_customer_params) do
    {
      sync_with_provider: true
    }
  end

  let_it_be(:customer) { create(:customer) }

  describe "#perform" do
    subject(:create_job) { described_class }

    before do
      allow(IntegrationCustomers::CreateService).to receive(:call!)
    end

    it "calls the create service" do
      described_class.perform_now(integration_customer_params:, integration:, customer:)

      expect(IntegrationCustomers::CreateService).to have_received(:call!)
    end
  end

  describe "#perform with a quickbooks integration" do
    let(:integration) { create(:quickbooks_integration) }
    let(:integration_customer_params) do
      {integration_type: "quickbooks", integration_code: integration.code, sync_with_provider: true}
    end

    let(:create_result) do
      result = Integrations::Aggregator::Contacts::CreateService::Result.new
      result.contact_id = "1042"
      result
    end

    before do
      allow(Integrations::Aggregator::Contacts::CreateService)
        .to receive(:call).and_return(create_result)
    end

    it "creates the contact in the provider and stores the integration customer" do
      expect { described_class.perform_now(integration_customer_params:, integration:, customer:) }
        .to change(IntegrationCustomers::QuickbooksCustomer, :count).by(1)

      expect(Integrations::Aggregator::Contacts::CreateService)
        .to have_received(:call).with(integration:, customer:, subsidiary_id: nil)
      expect(customer.reload.quickbooks_customer.external_customer_id).to eq("1042")
    end

    context "when the contact creation in the provider fails" do
      let(:create_result) do
        result = Integrations::Aggregator::Contacts::CreateService::Result.new
        result.service_failure!(code: "action_script_runtime_error", message: "Duplicate Name Exists Error")
        result
      end

      it "raises the failure" do
        expect { described_class.perform_now(integration_customer_params:, integration:, customer:) }
          .to raise_error(BaseService::ServiceFailure)
      end

      it "does not create integration customer" do
        expect do
          described_class.perform_now(integration_customer_params:, integration:, customer:)
        rescue BaseService::ServiceFailure
          nil
        end.not_to change(IntegrationCustomers::BaseCustomer, :count)
      end
    end
  end

  describe "#perform twice with a quickbooks integration, after a timeout" do
    let(:integration) { create(:quickbooks_integration) }
    let(:integration_customer_params) do
      {integration_type: "quickbooks", integration_code: integration.code, sync_with_provider: true}
    end
    let(:action_url) { "https://api.nango.dev/action/trigger" }
    let(:search_url) { "https://api.nango.dev/proxy/v3/company/1234567890/query" }
    let(:duplicate_name_body) do
      File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_duplicate_name_error.json"))
    end

    before do
      # The first create-customer times out after QuickBooks saved the customer, so the second one finds the name taken.
      stub_request(:post, action_url).to_raise(Net::ReadTimeout).then.to_return(status: 500, body: duplicate_name_body)
      stub_request(:get, search_url).with(query: hash_including({})).to_return(
        status: 200,
        body: {QueryResponse: {Customer: [{Id: "77", Notes: "Lago customer: #{customer.id} (#{customer.external_id})"}]}}.to_json
      )
    end

    it "links the customer created by the first run instead of creating a second one" do
      expect { described_class.perform_now(integration_customer_params:, integration:, customer:) }
        .to raise_error(Net::ReadTimeout)
      expect(customer.reload.quickbooks_customer).to be_nil

      described_class.perform_now(integration_customer_params:, integration:, customer:)

      expect(customer.reload.quickbooks_customer.external_customer_id).to eq("77")
      expect(WebMock).to have_requested(:post, action_url).twice
      expect(WebMock).to have_requested(:get, search_url).with(query: hash_including({})).once
    end
  end

  describe "#lock_key_arguments" do
    it "returns customer and integration for the lock key" do
      job = described_class.new(
        integration_customer_params: integration_customer_params,
        integration: integration,
        customer: customer
      )

      expect(job.lock_key_arguments).to eq([integration, customer])
    end
  end
end
