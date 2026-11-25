# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Contacts::CreateService do
  subject(:service_call) { described_class.call(integration:, customer:, subsidiary_id:) }

  let(:service) { described_class.new(integration:, customer:, subsidiary_id:) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { "https://api.nango.dev/action/trigger" }
  let(:action_name) { "#{integration_type}-create-contact" }
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
  let(:subsidiary_id) { "1" }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, :with_same_billing_and_shipping_address, organization:) }

  before do
    allow(LagoHttpClient::Client).to receive(:new)
      .with(endpoint, retries_on: [OpenSSL::SSL::SSLError])
      .and_return(lago_client)
  end

  describe "#call" do
    context "when service call is successful" do
      let(:response) { instance_double(Net::HTTPOK) }

      before do
        allow(lago_client).to receive(:post_with_response).with({action_name:, input: params}, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      context "when response is a string" do
        let(:integration) { create(:netsuite_integration, organization:) }
        let(:integration_type) { "netsuite" }
        let(:integration_type_key) { "netsuite-tba" }

        let(:params) do
          {
            "type" => "customer",
            "isDynamic" => true,
            "columns" => {
              "companyname" => customer.name,
              "isperson" => "F",
              "subsidiary" => subsidiary_id,
              "custentity_lago_id" => customer.id,
              "custentity_lago_sf_id" => customer.external_salesforce_id,
              "custentity_lago_customer_link" => customer_link,
              "email" => customer.email,
              "phone" => customer.phone,
              "entityid" => customer.external_id,
              "autoname" => false
            },
            "options" => {
              "ignoreMandatoryFields" => false
            },
            "lines" => [
              {
                "lineItems" => [
                  {
                    "defaultshipping" => true,
                    "defaultbilling" => true,
                    "subObjectId" => "addressbookaddress",
                    "subObject" => {
                      "addr1" => customer.address_line1,
                      "addr2" => customer.address_line2,
                      "city" => customer.city,
                      "zip" => customer.zipcode,
                      "state" => customer.state,
                      "country" => customer.country
                    }
                  }
                ],
                "sublistId" => "addressbook"
              }
            ]
          }
        end

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/contacts/success_string_response.json")
          File.read(path)
        end

        it "returns contact id" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("1")
        end

        it "delivers a success webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_created",
              customer
            ).on_queue(webhook_queue)
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
      end

      context "when response is a hash" do
        let(:integration) { create(:xero_integration, organization:) }
        let(:integration_type) { "xero" }
        let(:integration_type_key) { "xero" }

        let(:params) do
          [
            {
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

        context "when contact is succesfully created" do
          let(:body) do
            path = Rails.root.join("spec/fixtures/integration_aggregator/contacts/success_hash_response.json")
            File.read(path)
          end

          it "returns contact id" do
            result = service_call

            expect(result).to be_success
            expect(result.contact_id).to eq("2e50c200-9a54-4a66-b241-1e75fb87373f")
          end

          it "delivers a success webhook" do
            expect { service_call }.to enqueue_job(SendWebhookJob)
              .with(
                "customer.accounting_provider_created",
                customer
              ).on_queue(webhook_queue)
          end

          it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
        end

        context "when contact is not created" do
          let(:body) do
            path = Rails.root.join("spec/fixtures/integration_aggregator/contacts/failure_hash_response.json")
            File.read(path)
          end

          it "does not return contact id" do
            result = service_call

            expect(result).to be_success
            expect(result.contact_id).to be(nil)
          end

          it "does not create integration resource object" do
            expect { service_call }.not_to change(IntegrationResource, :count)
          end

          it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero
        end
      end
    end

    context "when service call is not successful" do
      let(:integration) { create(:netsuite_integration, organization:) }
      let(:integration_type) { "netsuite" }
      let(:integration_type_key) { "netsuite-tba" }

      let(:params) do
        {
          "type" => "customer",
          "isDynamic" => true,
          "columns" => {
            "companyname" => customer.name,
            "isperson" => "F",
            "subsidiary" => subsidiary_id,
            "custentity_lago_id" => customer.id,
            "custentity_lago_sf_id" => customer.external_salesforce_id,
            "custentity_lago_customer_link" => customer_link,
            "email" => customer.email,
            "phone" => customer.phone,
            "entityid" => customer.external_id,
            "autoname" => false
          },
          "options" => {
            "ignoreMandatoryFields" => false
          },
          "lines" => [
            {
              "lineItems" => [
                {
                  "defaultshipping" => true,
                  "defaultbilling" => true,
                  "subObjectId" => "addressbookaddress",
                  "subObject" => {
                    "addr1" => customer.address_line1,
                    "addr2" => customer.address_line2,
                    "city" => customer.city,
                    "zip" => customer.zipcode,
                    "state" => customer.state,
                    "country" => customer.country
                  }
                }
              ],
              "sublistId" => "addressbook"
            }
          ]
        }
      end

      let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }

      before do
        allow(lago_client).to receive(:post_with_response).with({action_name:, input: params}, headers).and_raise(http_error)
      end

      context "when it is a server error" do
        let(:error_code) { Faker::Number.between(from: 500, to: 599) }

        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/error_response.json")
          File.read(path)
        end

        it_behaves_like "throttles!", :anrok, :hubspot, :netsuite, :xero

        [
          {
            ctx: "when the error is not handled specifically",
            payload: {
              error: "An unexpected error occurred"
            },
            code: "unexpected_error",
            message: "{\"error\":\"An unexpected error occurred\"}"
          },
          {
            ctx: "when error is nested in `error.payload`",
            payload: {
              error: {
                message: "The action script failed with an error: {}",
                code: "action_script_failure",
                payload: {
                  error: "Error starting integration 'netsuite-customer-create': {\n  \"name\": \"TRPCClientError\",\n  \"message\": \"fetch failed\"\n}"
                }
              }
            },
            code: "action_script_failure",
            message: "Error starting integration 'netsuite-customer-create': {\n  \"name\": \"TRPCClientError\",\n  \"message\": \"fetch failed\"\n}"
          },
          {
            ctx: "when error is nested in `error.payload.error`",
            payload: {
              integration: "netsuite-tba",
              action: "netsuite-create-contact",
              connection: "netsuite-tba-xyz",
              error: {
                message: "An error occurred during an HTTP call",
                payload: {
                  error: {
                    code: "INVALID_LOGIN_ATTEMPT",
                    message: "Invalid login attempt."
                  }
                }
              }
            },
            code: "INVALID_LOGIN_ATTEMPT",
            message: "Invalid login attempt."
          },
          {
            ctx: "when error is nested in `payload.message`",
            payload: {
              type: "action_script_runtime_error",
              payload: {
                message: "submitFields: Missing a required argument: type"
              }
            },
            code: "action_script_runtime_error",
            message: "submitFields: Missing a required argument: type"
          }
        ].each do |test_case|
          ctx, payload, code, message = test_case.values_at(:ctx, :payload, :code, :message)
          context ctx do
            let(:body) { payload.to_json }
            let(:error_code) { 500 }
            let(:result) { service_call }

            it "returns an error" do
              expect { result }.to enqueue_job(SendWebhookJob)
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

              expect(result).not_to be_success
              expect(result.error.code).to eq(code)
              expect(result.error.message).to eq("#{code}: #{message}")
            end
          end
        end
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

    # The input and output follow Nango's catalog create-customer action (Intuit fields in, `id` out). The
    # error shape around Intuit's faults (duplicate name 6240, ThrottlingFault) is an assumption, to check
    # in a QuickBooks sandbox once the actions are deployed in Nango. Fixture values are invented.
    context "with a quickbooks integration" do
      let(:integration) { create(:quickbooks_integration, organization:) }
      let(:customer) do
        create(
          :customer,
          organization:,
          external_id: "cust-ext-1",
          name: "Example Co",
          legal_name: "Example Company SAS",
          firstname: "Ada",
          lastname: "Lovelace",
          email: "billing@example.com, ops@example.com",
          phone: "+33 1 23 45 67 89, +33 9 87 65 43 21",
          address_line1: "1 Main Street",
          address_line2: "Floor 2",
          city: "Paris",
          state: "IDF",
          zipcode: "75001",
          country: "FR",
          shipping_address_line1: "2 Dock Road",
          shipping_city: "Lyon",
          shipping_zipcode: "69001",
          shipping_country: "FR"
        )
      end
      let(:limiter) { instance_double(Throttling::Base) }
      let(:success_body) do
        File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_create_customer_response.json"))
      end
      let(:duplicate_name_body) do
        File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_duplicate_name_error.json"))
      end
      let(:other_error_body) do
        {
          error: {
            code: "action_script_failure",
            message: "Business Validation Error",
            payload: {Fault: {Error: [{Message: "Business Validation Error", code: "6000"}], type: "ValidationFault"}}
          }
        }.to_json
      end
      let(:expected_input) do
        {
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
          },
          "ShipAddr" => {
            "Line1" => "2 Dock Road",
            "City" => "Lyon",
            "PostalCode" => "69001",
            "Country" => "FR"
          },
          "Notes" => "Lago customer: #{customer.id} (cust-ext-1)"
        }
      end
      let(:unique_display_name) { "Example Co (cust-ext-1)" }
      let(:search_url) { "https://api.nango.dev/proxy/v3/company/1234567890/query" }
      let(:search_response) { {status: 200, body: {QueryResponse: {}}.to_json} }
      let(:throttled_body) do
        {
          Fault: {
            Error: [{Message: "message=ThrottleExceeded; errorCode=003001; statusCode=429", code: "3001"}],
            type: "ThrottlingFault"
          }
        }.to_json
      end

      before do
        allow(LagoHttpClient::Client).to receive(:new).and_call_original
        allow(Throttling).to receive(:for).and_call_original
        allow(Throttling).to receive(:for).with(:quickbooks).and_return(limiter)
        allow(limiter).to receive(:check).and_return(true)
        stub_request(:get, search_url).with(query: hash_including({})).to_return(search_response)
      end

      def enqueued_error_webhooks
        ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
          job["job_class"] == "SendWebhookJob" && job["arguments"].first == "customer.accounting_provider_error"
        end
      end

      def name_search(display_name)
        {query: {"query" => "select Id, Notes from Customer where DisplayName = '#{display_name}'"}}
      end

      context "when create-customer succeeds" do
        before { stub_request(:post, endpoint).to_return(status: 200, body: success_body) }

        it "sends one Intuit object to create-customer with the production provider config key" do
          service_call

          expect(WebMock).to have_requested(:post, endpoint)
            .with(
              body: {action_name: "create-customer", input: expected_input},
              headers: {"Provider-Config-Key" => "quickbooks", "Connection-Id" => "quickbooks-test-connection"}
            ).once
        end

        it "sends neither a currency nor a realm id" do
          service_call

          expect(WebMock).to(have_requested(:post, endpoint).with { |request|
            input = JSON.parse(request.body)["input"]
            !input.key?("CurrencyRef") && !input.key?("realmId")
          })
        end

        it "returns the QuickBooks customer id" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("58")
        end

        it "delivers the created webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with("customer.accounting_provider_created", customer)
            .on_queue(webhook_queue)
        end

        it "checks the QuickBooks throttle once" do
          service_call

          expect(limiter).to have_received(:check).with(:client, anything).once
        end

        context "when the throttle calls are spied on" do
          before do
            allow(described_class).to receive(:new).and_return(service)
            allow(service).to receive(:throttle!).and_call_original
          end

          it "does not use the shared throttle of the other providers" do
            service_call

            expect(service).to have_received(:throttle!).with(:quickbooks).once
            expect(service).not_to have_received(:throttle!).with(:anrok, :hubspot, :netsuite, :xero)
          end
        end

        context "with a sandbox integration" do
          let(:integration) do
            create(:quickbooks_integration, organization:, settings: {realm_id: "1234567890", sandbox: true})
          end

          it "uses the sandbox provider config key" do
            service_call

            expect(WebMock).to have_requested(:post, endpoint)
              .with(headers: {"Provider-Config-Key" => "quickbooks-sandbox"}).once
          end
        end
      end

      context "when the response has no customer id" do
        before { stub_request(:post, endpoint).to_return(status: 200, body: {displayName: "Example Co"}.to_json) }

        it "fails with customer_id_missing and delivers the error webhook" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "QuickBooks returned no customer id", error_code: "customer_id_missing"}
            )
          expect(result).to be_failure
          expect(result.error.code).to eq("customer_id_missing")
          expect(result.contact_id).to be_nil
        end

        it "does not deliver the created webhook" do
          expect { service_call }.not_to enqueue_job(SendWebhookJob).with("customer.accounting_provider_created", customer)
        end
      end

      context "when the response is not an object" do
        before { stub_request(:post, endpoint).to_return(status: 200, body: [{id: "58"}].to_json) }

        it "fails with customer_id_missing" do
          result = service_call

          expect(result).to be_failure
          expect(result.error.code).to eq("customer_id_missing")
          expect(result.contact_id).to be_nil
        end
      end

      context "when the name already exists and the retry succeeds" do
        let(:search_response) do
          {status: 200, body: {QueryResponse: {Customer: [{Id: "12", Notes: "Imported from the old ERP"}]}}.to_json}
        end

        before do
          stub_request(:post, endpoint).to_return(
            {status: 500, body: duplicate_name_body},
            {status: 200, body: success_body}
          )
        end

        it "searches the name, then retries once with the unique display name" do
          service_call

          expect(WebMock).to have_requested(:get, search_url).with(name_search("Example Co")).once
          expect(WebMock).to have_requested(:post, endpoint).twice
          expect(WebMock).to have_requested(:post, endpoint)
            .with(body: {action_name: "create-customer", input: expected_input.merge("DisplayName" => unique_display_name)})
            .once
        end

        it "returns the id of the retried call" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("58")
        end

        it "delivers the created webhook and no error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with("customer.accounting_provider_created", customer)
          expect(enqueued_error_webhooks).to be_empty
        end

        it "checks the QuickBooks throttle before each call" do
          service_call

          expect(limiter).to have_received(:check).with(:client, anything).exactly(3).times
        end

        context "when the throttle window is full before the name search" do
          before { allow(limiter).to receive(:check).and_return(true, false) }

          it "raises NextWindowThrottlingError without a search or a second call" do
            expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
            expect(WebMock).not_to have_requested(:get, search_url).with(query: hash_including({}))
            expect(WebMock).to have_requested(:post, endpoint).once
          end
        end
      end

      context "when the name is held by the customer Lago created in an earlier attempt" do
        let(:search_response) do
          {
            status: 200,
            body: {QueryResponse: {Customer: [{Id: "77", Notes: "Lago customer: #{customer.id} (cust-ext-1)"}]}}.to_json
          }
        end

        before { stub_request(:post, endpoint).to_return(status: 500, body: duplicate_name_body) }

        it "keeps the id of that customer without a second create-customer" do
          result = service_call

          expect(result).to be_success
          expect(result.contact_id).to eq("77")
          expect(WebMock).to have_requested(:post, endpoint).once
        end

        it "delivers the created webhook and no error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with("customer.accounting_provider_created", customer)
          expect(enqueued_error_webhooks).to be_empty
        end
      end

      context "when the name contains a single quote" do
        before do
          customer.update!(name: "O'Brien Co")
          stub_request(:post, endpoint).to_return(
            {status: 500, body: duplicate_name_body},
            {status: 200, body: success_body}
          )
        end

        it "escapes it in the name search" do
          service_call

          expect(WebMock).to have_requested(:get, search_url).with(name_search("O\\'Brien Co")).once
        end
      end

      context "when the name search fails" do
        let(:search_response) { {status: 500, body: {error: "fake-intuit-detail"}.to_json} }

        before { stub_request(:post, endpoint).to_return(status: 500, body: duplicate_name_body) }

        it "fails with customer_lookup_failed without a second create-customer" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "QuickBooks customer lookup failed", error_code: "customer_lookup_failed"}
            )
          expect(result).to be_failure
          expect(result.error.code).to eq("customer_lookup_failed")
          expect(WebMock).to have_requested(:post, endpoint).once
        end
      end

      context "when the name search is rate limited" do
        let(:search_response) { {status: 429, body: throttled_body} }

        before { stub_request(:post, endpoint).to_return(status: 500, body: duplicate_name_body) }

        it "raises NextWindowThrottlingError without a second create-customer or a webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(WebMock).to have_requested(:post, endpoint).once
          expect(enqueued_error_webhooks).to be_empty
        end
      end

      context "when the name already is the external id" do
        before do
          customer.update!(name: nil, firstname: nil, lastname: nil)
          stub_request(:post, endpoint).to_return(status: 500, body: duplicate_name_body)
        end

        it "searches the name, then fails without a suffixed retry" do
          result = service_call

          expect(WebMock).to have_requested(:get, search_url).with(name_search("cust-ext-1")).once
          expect(WebMock).to have_requested(:post, endpoint).once
          expect(result).to be_failure
          expect(enqueued_error_webhooks.size).to eq(1)
        end
      end

      context "when the duplicate-name code is under a capitalised Code key" do
        let(:duplicate_name_body) do
          {error: {code: "action_script_failure", message: "Duplicate", payload: {Fault: {Error: [{Code: 6240}]}}}}.to_json
        end

        before do
          stub_request(:post, endpoint).to_return(
            {status: 500, body: duplicate_name_body},
            {status: 200, body: success_body}
          )
        end

        it "retries once with the unique display name" do
          expect(service_call.contact_id).to eq("58")
          expect(WebMock).to have_requested(:post, endpoint).twice
        end
      end

      context "when the name already exists twice" do
        before { stub_request(:post, endpoint).to_return(status: 500, body: duplicate_name_body) }

        it "makes exactly two calls and searches both names" do
          service_call

          expect(WebMock).to have_requested(:post, endpoint).twice
          expect(WebMock).to have_requested(:get, search_url).with(name_search("Example Co")).once
          expect(WebMock).to have_requested(:get, search_url).with(name_search(unique_display_name)).once
        end

        it "fails and delivers one error webhook" do
          result = service_call

          expect(result).to be_failure
          expect(result.error.code).to eq("action_script_failure")
          expect(enqueued_error_webhooks.size).to eq(1)
        end

        it "delivers the error webhook with the provider error" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "Failed to create the customer in QuickBooks", error_code: "action_script_failure"}
            ).on_queue(webhook_queue)
        end

        it "keeps the realm id and connection id out of the webhook and the failure" do
          result = service_call

          exposed = [enqueued_error_webhooks.to_json, result.error.message, result.error.error_message.to_s].join
          expect(exposed).not_to include("1234567890")
          expect(exposed).not_to include("quickbooks-test-connection")
        end
      end

      context "when create-customer fails with another error" do
        before { stub_request(:post, endpoint).to_return(status: 500, body: other_error_body) }

        it "makes one call and delivers the error webhook" do
          result = nil

          expect { result = service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.accounting_provider_error",
              customer,
              provider: "quickbooks",
              provider_code: integration.code,
              provider_error: {message: "Business Validation Error", error_code: "action_script_failure"}
            )
          expect(WebMock).to have_requested(:post, endpoint).once
          expect(result).to be_failure
        end
      end

      context "when 6240 appears outside a code key or as part of another code" do
        let(:body) do
          {
            error: {
              code: "action_script_failure",
              message: "x",
              payload: {Fault: {Error: [{Message: "Other", Detail: "ref 6240", code: "62400"}]}}
            }
          }.to_json
        end

        before { stub_request(:post, endpoint).to_return(status: 500, body:) }

        it "makes one call, fails and delivers one error webhook" do
          result = service_call

          expect(WebMock).to have_requested(:post, endpoint).once
          expect(result).to be_failure
          expect(result.error.code).to eq("action_script_failure")
          expect(enqueued_error_webhooks.size).to eq(1)
        end
      end

      context "when the action error body is not JSON" do
        before { stub_request(:post, endpoint).to_return(status: 500, body: "Internal Server Error") }

        it "makes one call and fails" do
          expect(service_call).to be_failure
          expect(WebMock).to have_requested(:post, endpoint).once
        end
      end

      context "when QuickBooks answers 429" do
        before { stub_request(:post, endpoint).to_return(status: 429, body: throttled_body) }

        it "raises NextWindowThrottlingError without a webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(enqueued_error_webhooks).to be_empty
        end
      end

      context "when the action fails with Intuit's ThrottlingFault" do
        before do
          stub_request(:post, endpoint).to_return(
            status: 500,
            body: {error: {code: "action_script_failure", payload: JSON.parse(throttled_body)}}.to_json
          )
        end

        it "raises NextWindowThrottlingError without a webhook" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(enqueued_error_webhooks).to be_empty
        end
      end

      context "when the throttle window is full" do
        before do
          allow(limiter).to receive(:check).and_return(false)
          stub_request(:post, endpoint).to_return(status: 200, body: success_body)
        end

        it "raises NextWindowThrottlingError without calling Nango" do
          expect { service_call }.to raise_error(BaseService::NextWindowThrottlingError)
          expect(WebMock).not_to have_requested(:post, endpoint)
        end
      end
    end
  end

  describe "#process_hash_result" do
    subject(:process_hash_result) { service.send(:process_hash_result, body) }

    let(:result) { service.instance_variable_get(:@result) }
    let(:integration) { create(:hubspot_integration, organization:) }
    let(:integration_type) { "hubspot" }
    let(:integration_type_key) { "hubspot" }

    before do
      allow(service).to receive(:deliver_error_webhook)
    end

    context "when contact is successfully created" do
      let(:body) do
        {
          "succeededContacts" => [
            {
              "id" => "2e50c200-9a54-4a66-b241-1e75fb87373f",
              "email" => "billing@example.com"
            }
          ]
        }
      end

      it "sets the contact_id and email in the result" do
        process_hash_result

        expect(result.contact_id).to eq("2e50c200-9a54-4a66-b241-1e75fb87373f")
        expect(result.email).to eq("billing@example.com")
      end
    end

    context "when contact creation fails" do
      let(:body) do
        {
          "failedContacts" => [
            {
              "validation_errors" => [
                {"Message" => "Email is invalid"},
                {"Message" => "Name is required"}
              ]
            }
          ]
        }
      end

      it "delivers an error webhook" do
        process_hash_result

        expect(service).to have_received(:deliver_error_webhook).with(
          customer:,
          code: "Validation error",
          message: "Email is invalid. Name is required"
        )
      end
    end

    context "when there is a general error" do
      let(:body) do
        {
          "error" => {
            "payload" => {
              "message" => "An unexpected error occurred"
            }
          }
        }
      end

      it "delivers an error webhook" do
        process_hash_result

        expect(service).to have_received(:deliver_error_webhook).with(
          customer:,
          code: "Validation error",
          message: "An unexpected error occurred"
        )
      end
    end
  end

  describe "Nango action" do
    let(:response) { instance_double(Net::HTTPOK, body: '"1"') }

    before { allow(lago_client).to receive(:post_with_response).and_return(response) }

    context "with a HubSpot integration" do
      let(:integration) { create(:hubspot_integration, organization:) }

      it "triggers the create-contact action" do
        service_call

        expect(lago_client).to have_received(:post_with_response)
          .with(hash_including(action_name: "create-contact"), anything)
      end
    end

    context "with an Avalara integration" do
      let(:integration) { create(:avalara_integration, organization:) }

      it "triggers the create-customer action" do
        service_call

        expect(lago_client).to have_received(:post_with_response)
          .with(hash_including(action_name: "create-customer"), anything)
      end
    end
  end
end
