# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Contacts::UpdateService do
  subject(:service_call) { described_class.call(integration:, integration_customer:) }

  let(:service) { described_class.new(integration:, integration_customer:) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { "https://api.nango.dev/action/trigger" }
  let(:action_name) { "#{integration_type}-update-contact" }
  let(:headers) do
    {
      "Connection-Id" => integration.connection_id,
      "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      "Provider-Config-Key" => integration_type_key
    }
  end
  let(:customer_link) do
    url = Rails.application.config.lago_front_url

    URI.join(url, "/#{customer.organization.slug}/customer/", customer.id).to_s
  end

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }

  before do
    allow(LagoHttpClient::Client).to receive(:new)
      .with(endpoint, retries_on: [OpenSSL::SSL::SSLError])
      .and_return(lago_client)
  end

  describe "#call" do
    context "when service call is successful" do
      let(:response) { instance_double(Net::HTTPOK) }
      let(:code) { 200 }

      context "when response is a string" do
        let(:integration) { create(:netsuite_integration, organization:) }
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration_type) { "netsuite" }
        let(:integration_type_key) { "netsuite-tba" }

        let(:params) do
          {
            "type" => "customer",
            "recordId" => integration_customer.external_customer_id,
            "columns" => {
              "companyname" => customer.name,
              "isperson" => "F",
              "subsidiary" => integration_customer.subsidiary_id,
              "custentity_lago_sf_id" => customer.external_salesforce_id,
              "custentity_lago_customer_link" => customer_link,
              "email" => customer.email,
              "phone" => customer.phone,
              "entityid" => customer.external_id,
              "autoname" => false
            },
            "options" => {
              "isDynamic" => false
            }
          }
        end

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/contacts/success_string_response.json")
          File.read(path)
        end

        before do
          allow(lago_client).to receive(:post_with_response).with({action_name:, input: params}, headers).and_return(response)
          allow(response).to receive(:body).and_return(body)
        end

        it "returns contact id" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("1")
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end

      context "when response is a hash" do
        let(:integration) { create(:xero_integration, organization:) }
        let(:integration_customer) { create(:xero_customer, integration:, customer:) }
        let(:integration_type) { "xero" }
        let(:integration_type_key) { "xero" }

        let(:params) do
          [
            {
              "id" => integration_customer.external_customer_id,
              "name" => customer.name,
              "firstname" => customer.firstname,
              "lastname" => customer.lastname,
              "email" => customer.email,
              "city" => customer.city,
              "zip" => customer.zipcode,
              "country" => customer.country,
              "state" => customer.state,
              "phone" => customer.phone
            }
          ]
        end

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/contacts/success_hash_response.json")
          File.read(path)
        end

        before do
          allow(lago_client).to receive(:post_with_response).with({action_name:, input: params}, headers).and_return(response)
          allow(response).to receive(:body).and_return(body)
        end

        it "returns contact id" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("2e50c200-9a54-4a66-b241-1e75fb87373f")
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end
    end

    context "when service call is not successful" do
      let(:integration) { create(:netsuite_integration, organization:) }
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
      let(:integration_type) { "netsuite" }
      let(:integration_type_key) { "netsuite-tba" }

      let(:params) do
        {
          "type" => "customer",
          "recordId" => integration_customer.external_customer_id,
          "columns" => {
            "companyname" => customer.name,
            "isperson" => "F",
            "subsidiary" => integration_customer.subsidiary_id,
            "custentity_lago_sf_id" => customer.external_salesforce_id,
            "custentity_lago_customer_link" => customer_link,
            "email" => customer.email,
            "phone" => customer.phone,
            "entityid" => customer.external_id,
            "autoname" => false
          },
          "options" => {
            "isDynamic" => false
          }
        }
      end

      let(:body) do
        path = Rails.root.join("spec/fixtures/integration_aggregator/error_response.json")
        File.read(path)
      end

      let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }

      before do
        allow(lago_client).to receive(:post_with_response).with({action_name:, input: params}, headers).and_raise(http_error)
      end

      context "when it is a server error" do
        let(:error_code) { Faker::Number.between(from: 500, to: 599) }
        let(:code) { "action_script_runtime_error" }
        let(:message) { "submitFields: Missing a required argument: type" }

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/error_response.json")
          File.read(path)
        end

        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error.code).to eq("action_script_runtime_error")
          expect(result.error.message)
            .to eq("action_script_runtime_error: submitFields: Missing a required argument: type")
        end

        it "delivers an error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "netsuite",
              provider_code: integration.code,
              provider_error: {
                message: "submitFields: Missing a required argument: type",
                error_code: "action_script_runtime_error"
              }
            )
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end

      context "when it is a server payload error" do
        let(:error_code) { Faker::Number.between(from: 500, to: 599) }
        let(:code) { "TypeError" }
        let(:message) { "Please enter value(s) for: Company Name" }

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/error_payload_response.json")
          File.read(path)
        end

        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error.code).to eq(code)
          expect(result.error.message).to eq("#{code}: #{message}")
        end

        it "delivers an error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "netsuite",
              provider_code: integration.code,
              provider_error: {
                message:,
                error_code: code
              }
            )
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end

      context "when it is a client error" do
        let(:error_code) { 404 }
        let(:code) { "invalid_secret_key_format" }
        let(:message) { "Authentication failed. The provided secret key is not a UUID v4." }

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/error_auth_response.json")
          File.read(path)
        end

        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error.code).to eq(code)
          expect(result.error.message).to eq("#{code}: #{message}")
        end

        it "delivers an error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "netsuite",
              provider_code: integration.code,
              provider_error: {
                message:,
                error_code: code
              }
            )
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end

      context "when it is a request limit error" do
        let(:error_code) { 429 }
        let(:body) { {error: {code: "SSS_REQUEST_LIMIT_EXCEEDED"}}.to_json }

        it "raises RequestLimitError" do
          expect { service_call }.to raise_error(Integrations::Aggregator::RequestLimitError)
        end
      end
    end

    # The input and output follow Nango's catalog update-customer action (Intuit fields, Id and SyncToken in,
    # `id` out). The error shape around Intuit's faults is an assumption, to check in a QuickBooks sandbox once
    # the actions are deployed in Nango. Fixture values are invented.
    context "with a quickbooks integration" do
      let(:integration) { create(:quickbooks_integration, organization:) }
      let(:integration_customer) { create(:quickbooks_customer, integration:, customer:, external_customer_id: "58") }
      let(:customer) do
        create(
          :customer,
          organization:,
          external_id: "cust-ext-1",
          name: "Example Co",
          legal_name: "Example Company SAS",
          firstname: "Ada",
          lastname: "Lovelace",
          email: "billing@example.com",
          phone: "+33 1 23 45 67 89",
          address_line1: "1 Main Street",
          address_line2: "Floor 2",
          city: "Paris",
          state: "IDF",
          zipcode: "75001",
          country: "FR"
        )
      end
      let(:proxy_url) { "https://api.nango.dev/proxy/v3/company/1234567890/customer/58" }
      let(:limiter) { instance_double(Throttling::Base) }
      let(:calls) { [] }
      let(:log_output) { StringIO.new }
      let(:proxy_response) do
        {
          status: 200,
          body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_customer_proxy_response.json"))
        }
      end
      let(:success_response) do
        {
          status: 200,
          body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_update_customer_response.json"))
        }
      end
      let(:duplicate_name_response) do
        {
          status: 500,
          body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_duplicate_name_error.json"))
        }
      end
      let(:other_error_response) do
        {
          status: 500,
          body: {
            error: {
              code: "action_script_failure",
              message: "Business Validation Error",
              payload: {Fault: {Error: [{Message: "Business Validation Error", code: "6000"}], type: "ValidationFault"}}
            }
          }.to_json
        }
      end
      let(:throttled_body) do
        {
          Fault: {
            Error: [{Message: "message=ThrottleExceeded; errorCode=003001; statusCode=429", code: "3001"}],
            type: "ThrottlingFault"
          }
        }.to_json
      end
      let(:action_responses) { [success_response] }
      let(:expected_input) do
        {
          "Id" => "58",
          "SyncToken" => "3",
          "sparse" => true,
          "DisplayName" => "Example Co",
          "CompanyName" => "Example Company SAS",
          "GivenName" => "Ada",
          "FamilyName" => "Lovelace",
          "PrimaryEmailAddr" => {"Address" => "billing@example.com"},
          "PrimaryPhone" => {"FreeFormNumber" => "+33 1 23 45 67 89"},
          "BillAddr" => {
            "Line1" => "1 Main Street",
            "Line2" => "Floor 2",
            "City" => "Paris",
            "CountrySubDivisionCode" => "IDF",
            "PostalCode" => "75001",
            "Country" => "FR"
          }
        }
      end

      before do
        allow(LagoHttpClient::Client).to receive(:new).and_call_original
        allow(Throttling).to receive(:for).and_call_original
        allow(Throttling).to receive(:for).with(:quickbooks).and_return(limiter)
        allow(limiter).to receive(:check).and_return(true)
        allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

        stub_request(:get, proxy_url).to_return do
          calls << :proxy
          proxy_response
        end

        responses = action_responses.dup
        stub_request(:post, endpoint).to_return do
          calls << :action
          if responses.size > 1
            responses.shift
          else
            responses.first
          end
        end
      end

      def enqueued_webhooks(webhook_code)
        ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
          job["job_class"] == "SendWebhookJob" && job["arguments"].first == webhook_code
        end
      end

      def exposed_text(result)
        [
          enqueued_webhooks("customer.accounting_provider_error").to_json,
          result.error&.message.to_s,
          result.error.try(:error_message).to_s,
          log_output.string
        ].join
      end

      shared_examples "a quickbooks update failure without update-customer" do |error_code, error_message|
        it "delivers the error webhook and makes no update-customer call" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: error_message, error_code:}
            ).on_queue(webhook_queue)
          expect(result).to be_failure
          expect(result.error.code).to eq(error_code)
          expect(WebMock).not_to have_requested(:post, endpoint)
        end

        it "keeps the realm id and connection id out of the webhook, the failure and the logs" do
          result = service_call

          expect(exposed_text(result)).not_to include("1234567890")
          expect(exposed_text(result)).not_to include("quickbooks-test-connection")
        end
      end

      context "when update-customer succeeds" do
        it "reads the SyncToken through the proxy, then sends update-customer with Id, SyncToken and sparse" do
          service_call

          expect(calls).to eq(%i[proxy action])
          expect(WebMock).to have_requested(:get, proxy_url)
            .with(headers: {"Provider-Config-Key" => "quickbooks", "Connection-Id" => "quickbooks-test-connection"}).once
          expect(WebMock).to have_requested(:post, endpoint)
            .with(
              body: {action_name: "update-customer", input: expected_input},
              headers: {"Provider-Config-Key" => "quickbooks", "Connection-Id" => "quickbooks-test-connection"}
            ).once
        end

        it "sends neither Notes nor a currency" do
          service_call

          expect(WebMock).to(have_requested(:post, endpoint).with { |request|
            input = JSON.parse(request.body)["input"]
            !input.key?("Notes") && !input.key?("CurrencyRef")
          })
        end

        it "returns the QuickBooks customer id and delivers no webhook" do
          result = nil

          expect { result = service_call }.not_to have_enqueued_job(SendWebhookJob)
          expect(result).to be_success
          expect(result.contact_id).to eq("58")
        end

        it "checks the QuickBooks throttle once per Nango call" do
          service_call

          expect(limiter).to have_received(:check).with(:client, anything).twice
        end

        context "when the throttle calls are spied on" do
          before do
            allow(described_class).to receive(:new).and_return(service)
            allow(service).to receive(:throttle!).and_call_original
          end

          it "does not use the shared throttle of the other providers" do
            service_call

            expect(service).not_to have_received(:throttle!).with(:anrok, :hubspot, :netsuite, :xero)
          end
        end
      end

      context "when update-customer returns no customer id" do
        let(:action_responses) { [{status: 200, body: {displayName: "Example Co"}.to_json}] }

        it "fails with customer_id_missing and delivers the error webhook" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "QuickBooks returned no customer id", error_code: "customer_id_missing"}
            ).on_queue(webhook_queue)
          expect(result).to be_failure
          expect(result.error.code).to eq("customer_id_missing")
          expect(result.contact_id).to be_nil
        end
      end

      context "when the throttle window is full before update-customer" do
        before { allow(limiter).to receive(:check).and_return(true, false) }

        it "raises NextWindowThrottlingError after the proxy read and without update-customer" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(WebMock).to have_requested(:get, proxy_url).once
          expect(WebMock).not_to have_requested(:post, endpoint)
        end
      end

      context "when the proxy read fails" do
        let(:proxy_response) { {status: 500, body: {error: "fake-intuit-detail"}.to_json} }

        it_behaves_like "a quickbooks update failure without update-customer",
          "customer_lookup_failed", "QuickBooks customer lookup failed"
      end

      context "when the QuickBooks customer no longer exists" do
        let(:proxy_response) { {status: 404, body: {Fault: {Error: [{code: "610"}]}}.to_json} }

        it_behaves_like "a quickbooks update failure without update-customer",
          "customer_not_found", "QuickBooks customer not found"
      end

      context "when the proxy read times out" do
        before { stub_request(:get, proxy_url).to_timeout }

        it_behaves_like "a quickbooks update failure without update-customer",
          "customer_lookup_failed", "QuickBooks customer lookup failed"
      end

      context "when the proxy response has no SyncToken" do
        let(:proxy_response) { {status: 200, body: {Customer: {Id: "58"}}.to_json} }

        it_behaves_like "a quickbooks update failure without update-customer",
          "sync_token_missing", "QuickBooks customer has no SyncToken"
      end

      context "when the connection has no realm id" do
        let(:integration) do
          create(:quickbooks_integration, organization:, settings: {realm_id: nil, sandbox: false})
        end

        it_behaves_like "a quickbooks update failure without update-customer",
          "realm_id_missing", "QuickBooks connection has no company id"

        it "makes no request at all" do
          service_call

          expect(calls).to be_empty
          expect(limiter).not_to have_received(:check)
        end
      end

      context "when the QuickBooks customer was created under the suffixed name" do
        let(:proxy_response) do
          {status: 200, body: {Customer: {Id: "58", SyncToken: "3", DisplayName: "Example Co (cust-ext-1)"}}.to_json}
        end

        it "keeps the suffixed name" do
          service_call

          expect(WebMock).to have_requested(:post, endpoint)
            .with(body: {action_name: "update-customer", input: expected_input.merge("DisplayName" => "Example Co (cust-ext-1)")})
            .once
        end
      end

      context "when the QuickBooks customer has another name" do
        let(:proxy_response) do
          {status: 200, body: {Customer: {Id: "58", SyncToken: "3", DisplayName: "Old Name"}}.to_json}
        end

        it "sends the Lago name" do
          service_call

          expect(WebMock).to have_requested(:post, endpoint).with(body: {action_name: "update-customer", input: expected_input}).once
        end
      end

      context "when the name already exists" do
        let(:action_responses) { [duplicate_name_response] }

        it "makes one update-customer call without renaming the customer" do
          service_call

          expect(calls).to eq(%i[proxy action])
          expect(WebMock).to have_requested(:post, endpoint).with(body: {action_name: "update-customer", input: expected_input}).once
        end

        it "fails and delivers the error webhook with the provider error" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "Failed to create the customer in QuickBooks", error_code: "action_script_failure"}
            ).on_queue(webhook_queue)
          expect(result).to be_failure
          expect(enqueued_webhooks("customer.accounting_provider_error").size).to eq(1)
        end

        it "keeps the realm id and connection id out of the webhook, the failure and the logs" do
          result = service_call

          expect(exposed_text(result)).not_to include("1234567890")
          expect(exposed_text(result)).not_to include("quickbooks-test-connection")
        end
      end

      context "when update-customer fails with another error" do
        let(:action_responses) { [other_error_response] }

        it "makes one call, fails and delivers the error webhook" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "Business Validation Error", error_code: "action_script_failure"}
            )
          expect(result).to be_failure
          expect(WebMock).to have_requested(:post, endpoint).once
        end
      end

      context "when QuickBooks answers 429 to update-customer" do
        let(:action_responses) { [{status: 429, body: throttled_body}] }

        it "raises NextWindowThrottlingError without an error webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(enqueued_webhooks("customer.accounting_provider_error")).to be_empty
        end
      end

      context "when update-customer fails with Intuit's ThrottlingFault" do
        let(:action_responses) do
          [{status: 500, body: {error: {code: "action_script_failure", payload: JSON.parse(throttled_body)}}.to_json}]
        end

        it "raises NextWindowThrottlingError without an error webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(enqueued_webhooks("customer.accounting_provider_error")).to be_empty
        end
      end

      context "when the proxy read is rate limited" do
        let(:proxy_response) { {status: 429, body: throttled_body} }

        it "raises NextWindowThrottlingError without update-customer or a webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(WebMock).not_to have_requested(:post, endpoint)
          expect(enqueued_webhooks("customer.accounting_provider_error")).to be_empty
        end
      end
    end
  end

  describe "Nango action" do
    let(:response) { instance_double(Net::HTTPOK, body: '"1"') }

    before { allow(lago_client).to receive(:post_with_response).and_return(response) }

    context "with a HubSpot integration" do
      let(:integration) { create(:hubspot_integration, organization:) }
      let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }

      it "triggers the update-contact action" do
        service_call

        expect(lago_client).to have_received(:post_with_response)
          .with(hash_including(action_name: "update-contact"), anything)
      end
    end

    context "with an Avalara integration" do
      let(:integration) { create(:avalara_integration, organization:) }
      let(:integration_customer) { create(:avalara_customer, integration:, customer:) }

      it "triggers the update-customer action" do
        service_call

        expect(lago_client).to have_received(:post_with_response)
          .with(hash_including(action_name: "update-customer"), anything)
      end
    end

    context "with a QuickBooks integration" do
      let(:integration) { create(:quickbooks_integration, organization:) }
      let(:integration_customer) { create(:quickbooks_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK, body: {id: "58"}.to_json) }
      let(:sync_token_result) do
        Integrations::Aggregator::Contacts::FetchQuickbooksSyncTokenService::Result.new.tap { |r| r.sync_token = "3" }
      end

      before do
        allow(Integrations::Aggregator::Contacts::FetchQuickbooksSyncTokenService).to receive(:call)
          .and_return(sync_token_result)
      end

      it "triggers the update-customer action" do
        service_call

        expect(lago_client).to have_received(:post_with_response)
          .with(hash_including(action_name: "update-customer"), anything)
      end
    end
  end
end
