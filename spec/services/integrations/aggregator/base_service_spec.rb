# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::BaseService do
  subject(:sync_service) { described_class.new(integration:) }

  before_all do
    create_default(:organization)
  end

  let(:integration) { create(:netsuite_integration) }

  describe "#request_limit_error?" do
    let(:http_error) { instance_double(LagoHttpClient::HttpError, error_body:) }

    context "when error body includes request limit error code" do
      let(:error_body) { "Some error message including SSS_REQUEST_LIMIT_EXCEEDED" }

      it "returns true" do
        expect(sync_service.send(:request_limit_error?, http_error)).to be true
      end
    end

    context "when error body does not include request limit error code" do
      let(:error_body) { "Some other error message" }

      it "returns false" do
        expect(sync_service.send(:request_limit_error?, http_error)).to be false
      end
    end
  end

  describe "#throttle!" do
    subject(:throttle) { service.send(:throttle!, provider_name) }

    let(:limiter) { instance_double(Throttling::Base, check: allowed) }
    let(:allowed) { false }

    let(:service) do
      throttled_provider = provider_name.to_s

      Class.new(described_class) do
        define_method(:provider) { throttled_provider }
        define_method(:throttle_key) { "throttle-key" }
      end.new(integration:)
    end

    before do
      allow(Throttling).to receive(:for).with(provider_name).and_return(limiter)
    end

    %i[netsuite xero hubspot anrok avalara].each do |existing_provider|
      context "when #{existing_provider} is rate limited" do
        let(:provider_name) { existing_provider }

        it "raises the regular throttling error" do
          expect { throttle }
            .to raise_error(BaseService::ThrottlingError) { |error| expect(error.provider_name).to eq(provider_name) }
        end
      end
    end

    context "when quickbooks is rate limited" do
      let(:provider_name) { :quickbooks }

      it "raises the next window throttling error, retried after 60 seconds when no limit is configured" do
        allow(Throttling).to receive(:limits).and_return({})

        expect { throttle }
          .to raise_error(BaseService::NextWindowThrottlingError) do |error|
            expect(error.provider_name).to eq(:quickbooks)
            expect(error.retry_after).to eq(60.seconds)
          end
      end

      context "with a flat limit entry" do
        before do
          allow(Throttling).to receive(:limits).and_return({quickbooks: {limit: 1, period: 60}})
        end

        it "retries when the current window ends" do
          travel_to(Time.zone.parse("2026-11-23 10:00:20")) do
            expect { throttle }
              .to raise_error(BaseService::NextWindowThrottlingError) { |error| expect(error.retry_after).to eq(40.seconds) }
          end
        end
      end

      context "with a minutely limit" do
        before do
          allow(Throttling).to receive(:limits).and_return({quickbooks: {minutely: {limit: 1, period: 60}}})
        end

        it "retries when the current window ends" do
          travel_to(Time.zone.parse("2026-11-23 10:00:05")) do
            expect { throttle }
              .to raise_error(BaseService::NextWindowThrottlingError) { |error| expect(error.retry_after).to eq(55.seconds) }
          end
        end

        it "waits a full window at the start of a minute" do
          travel_to(Time.zone.parse("2026-11-23 10:00:00")) do
            expect { throttle }
              .to raise_error(BaseService::NextWindowThrottlingError) { |error| expect(error.retry_after).to eq(60.seconds) }
          end
        end
      end
    end

    context "when the provider is not rate limited" do
      let(:provider_name) { :quickbooks }
      let(:allowed) { true }

      it "does not raise" do
        expect { throttle }.not_to raise_error
      end
    end
  end

  describe "#trigger_action" do
    let(:service) do
      Class.new(described_class) do
        def action_name
          "netsuite-create-invoice"
        end
      end.new(integration:)
    end
    let(:lago_client) { instance_double(LagoHttpClient::Client, post_with_response: nil) }

    before do
      allow(LagoHttpClient::Client).to receive(:new).and_return(lago_client)
      allow(Sentry).to receive(:set_tags)
    end

    it "posts the action name and input" do
      service.send(:trigger_action, {foo: "bar"})

      expect(lago_client).to have_received(:post_with_response)
        .with({action_name: "netsuite-create-invoice", input: {foo: "bar"}}, anything)
    end

    it "tags the Nango action for error reporting" do
      service.send(:trigger_action, {foo: "bar"})

      expect(Sentry).to have_received(:set_tags).with(nango_action: "netsuite-create-invoice")
    end
  end

  describe "#provider and #provider_key" do
    subject(:service) { described_class.new(integration:) }

    context "with a NetSuite integration" do
      let(:integration) { create(:netsuite_integration) }

      it "uses the netsuite provider and the netsuite-tba key" do
        expect(service.send(:provider)).to eq("netsuite")
        expect(service.send(:provider_key)).to eq("netsuite-tba")
      end
    end

    context "with a Xero integration" do
      let(:integration) { create(:xero_integration) }

      it "uses the xero provider and key" do
        expect(service.send(:provider)).to eq("xero")
        expect(service.send(:provider_key)).to eq("xero")
      end
    end

    context "with an Anrok integration" do
      let(:integration) { create(:anrok_integration) }

      it "uses the anrok provider and key" do
        expect(service.send(:provider)).to eq("anrok")
        expect(service.send(:provider_key)).to eq("anrok")
      end
    end

    context "with a HubSpot integration" do
      let(:integration) { create(:hubspot_integration) }

      it "uses the hubspot provider and key" do
        expect(service.send(:provider)).to eq("hubspot")
        expect(service.send(:provider_key)).to eq("hubspot")
      end
    end

    context "with an Avalara integration" do
      let(:integration) { create(:avalara_integration) }

      it "uses the avalara provider" do
        expect(service.send(:provider)).to eq("avalara")
      end

      context "when Rails runs in production" do
        before { allow(Rails.env).to receive(:production?).and_return(true) }

        it "uses the avalara key" do
          expect(service.send(:provider_key)).to eq("avalara")
        end
      end

      context "when Rails does not run in production" do
        before { allow(Rails.env).to receive(:production?).and_return(false) }

        it "uses the avalara-sandbox key" do
          expect(service.send(:provider_key)).to eq("avalara-sandbox")
        end
      end
    end

    context "with a QuickBooks integration" do
      let(:integration) { create(:quickbooks_integration, settings:) }
      let(:settings) { {realm_id: "1234567890", sandbox:} }
      let(:sandbox) { false }

      it "uses the quickbooks provider" do
        expect(service.send(:provider)).to eq("quickbooks")
      end

      [true, "true"].each do |value|
        context "when sandbox is #{value.inspect}" do
          let(:sandbox) { value }

          it "uses the quickbooks-sandbox key" do
            expect(service.send(:provider_key)).to eq("quickbooks-sandbox")
          end
        end
      end

      [false, "false", nil, "False", "no", 1].each do |value|
        context "when sandbox is #{value.inspect}" do
          let(:sandbox) { value }

          it "uses the quickbooks key" do
            expect(service.send(:provider_key)).to eq("quickbooks")
          end
        end
      end

      context "when sandbox is absent from the settings" do
        let(:settings) { {realm_id: "1234567890"} }

        it "uses the quickbooks key" do
          expect(service.send(:provider_key)).to eq("quickbooks")
        end
      end

      context "when Rails runs in production and sandbox is true" do
        let(:sandbox) { true }

        before { allow(Rails.env).to receive(:production?).and_return(true) }

        it "still uses the quickbooks-sandbox key" do
          expect(service.send(:provider_key)).to eq("quickbooks-sandbox")
        end
      end

      context "when Rails does not run in production and sandbox is false" do
        before { allow(Rails.env).to receive(:production?).and_return(false) }

        it "still uses the quickbooks key" do
          expect(service.send(:provider_key)).to eq("quickbooks")
        end
      end

      describe "request headers" do
        context "when sandbox is true" do
          let(:sandbox) { true }

          it "sends the sandbox provider config key for the connection" do
            expect(service.send(:headers)).to include(
              "Provider-Config-Key" => "quickbooks-sandbox",
              "Connection-Id" => "quickbooks-test-connection"
            )
          end
        end

        context "when sandbox is false" do
          it "sends the production provider config key for the connection" do
            expect(service.send(:headers)).to include(
              "Provider-Config-Key" => "quickbooks",
              "Connection-Id" => "quickbooks-test-connection"
            )
          end
        end
      end
    end
  end

  describe "#throttle_key" do
    subject(:throttle_key) { described_class.new(integration:).send(:throttle_key) }

    context "with QuickBooks integrations" do
      def quickbooks_integration(connection_id:, realm_id:, sandbox: false, organization: create(:organization))
        create(
          :quickbooks_integration,
          organization:,
          secrets: {connection_id:}.to_json,
          settings: {realm_id:, sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false}
        )
      end

      def key_for(integration)
        described_class.new(integration:).send(:throttle_key)
      end

      let(:integration_a) { quickbooks_integration(connection_id: "quickbooks-placeholder-connection-a", realm_id: "1111111111") }
      let(:integration_b) { quickbooks_integration(connection_id: "quickbooks-placeholder-connection-b", realm_id: "2222222222") }

      it "uses the SHA-256 digest of the provider key and the company id" do
        expect(key_for(integration_a)).to eq(Digest::SHA2.hexdigest("quickbooks:1111111111"))
        expect(key_for(integration_b)).to eq(Digest::SHA2.hexdigest("quickbooks:2222222222"))
      end

      it "gives different keys to different companies" do
        expect(key_for(integration_a)).not_to eq(key_for(integration_b))
      end

      it "gives the same key to two connections to the same company" do
        other = quickbooks_integration(connection_id: "quickbooks-placeholder-connection-c", realm_id: "1111111111")

        expect(key_for(other)).to eq(key_for(integration_a))
      end

      it "keeps a sandbox company apart from a production company with the same id" do
        sandbox = quickbooks_integration(connection_id: "quickbooks-placeholder-connection-c", realm_id: "1111111111", sandbox: true)

        expect(key_for(sandbox)).to eq(Digest::SHA2.hexdigest("quickbooks-sandbox:1111111111"))
        expect(key_for(sandbox)).not_to eq(key_for(integration_a))
      end

      it "falls back to the digest of the connection id when the company id is blank" do
        integration = quickbooks_integration(connection_id: "quickbooks-placeholder-connection-c", realm_id: nil)

        expect(key_for(integration)).to eq(Digest::SHA2.hexdigest("quickbooks-placeholder-connection-c"))
      end
    end

    context "with a NetSuite integration" do
      let(:integration) { create(:netsuite_integration) }

      it "uses the SHA-256 digest of the client id" do
        expect(throttle_key).to eq(Digest::SHA2.hexdigest(integration.client_id))
      end
    end

    context "with an Anrok integration" do
      let(:integration) { create(:anrok_integration) }

      it "uses the SHA-256 digest of the api key" do
        expect(throttle_key).to eq(Digest::SHA2.hexdigest(integration.api_key))
      end
    end

    {xero_integration: "xero", hubspot_integration: "hubspot", avalara_integration: "avalara"}.each do |factory, key|
      context "with a #{key} integration" do
        let(:integration) { create(factory) }

        it "uses the global #{key} key" do
          expect(throttle_key).to eq(key)
        end
      end
    end
  end

  describe "#throttle! with a real counter" do
    def quickbooks_integration(connection_id:, realm_id:, sandbox: false, organization: create(:organization))
      create(
        :quickbooks_integration,
        organization:,
        secrets: {connection_id:}.to_json,
        settings: {realm_id:, sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false}
      )
    end

    let(:store) { ActiveSupport::Cache::MemoryStore.new }
    let(:store_keys) { store.instance_variable_get(:@data).keys }

    let(:connection_id_a) { "quickbooks-placeholder-connection-a" }
    let(:connection_id_b) { "quickbooks-placeholder-connection-b" }
    let(:integration_a) { quickbooks_integration(connection_id: connection_id_a, realm_id: "1111111111") }
    let(:integration_b) { quickbooks_integration(connection_id: connection_id_b, realm_id: "2222222222") }
    let(:service_a) { described_class.new(integration: integration_a) }
    let(:service_b) { described_class.new(integration: integration_b) }

    before do
      allow(Throttling).to receive(:storage).and_return(store)
      travel_to(Time.zone.parse("2026-01-05 10:00:00"))
    end

    it "allows 150 QuickBooks calls a minute and waits for the next window on the 151st" do
      expect { 150.times { service_a.send(:throttle!, :quickbooks) } }.not_to raise_error

      expect { service_a.send(:throttle!, :quickbooks) }
        .to raise_error(BaseService::NextWindowThrottlingError) do |error|
          expect(error.provider_name).to eq(:quickbooks)
          expect(error.retry_after).to eq(60.seconds)
        end
    end

    it "counts each QuickBooks company apart and never stores the company or connection id" do
      150.times { service_a.send(:throttle!, :quickbooks) }

      expect { service_a.send(:throttle!, :quickbooks) }
        .to raise_error(BaseService::NextWindowThrottlingError) do |error|
          expect(error.message).not_to include(connection_id_a)
        end
      expect { service_b.send(:throttle!, :quickbooks) }.not_to raise_error

      expect(store_keys).to include(a_string_including(Digest::SHA2.hexdigest("quickbooks:1111111111")))
      expect(store_keys).to include(a_string_including(Digest::SHA2.hexdigest("quickbooks:2222222222")))
      expect(store_keys).to all(start_with("throttle:quickbooks:client:"))
      expect(store_keys.join).not_to include("1111111111")
      expect(store_keys.join).not_to include(connection_id_a)
    end

    it "shares one counter between two organizations connected to the same company" do
      other_org = quickbooks_integration(connection_id: "quickbooks-placeholder-connection-c", realm_id: "1111111111")

      150.times { service_a.send(:throttle!, :quickbooks) }

      expect { described_class.new(integration: other_org).send(:throttle!, :quickbooks) }
        .to raise_error(BaseService::NextWindowThrottlingError)
    end

    it "counts a sandbox company apart from a production company with the same id" do
      sandbox = quickbooks_integration(connection_id: "quickbooks-placeholder-connection-c", realm_id: "1111111111", sandbox: true)

      150.times { service_a.send(:throttle!, :quickbooks) }

      expect { described_class.new(integration: sandbox).send(:throttle!, :quickbooks) }.not_to raise_error
    end

    it "still raises the regular throttling error on the 11th NetSuite call in a second" do
      service = described_class.new(integration: create(:netsuite_integration))

      expect { 10.times { service.send(:throttle!, :netsuite) } }.not_to raise_error
      expect { service.send(:throttle!, :netsuite) }
        .to raise_error(BaseService::ThrottlingError) { |error| expect(error.provider_name).to eq(:netsuite) }
    end
  end
end
