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

      [false, "false", nil].each do |value|
        context "when sandbox is #{value.inspect}" do
          let(:sandbox) { value }

          it "uses the quickbooks key" do
            expect(service.send(:provider_key)).to eq("quickbooks")
          end
        end
      end

      ["False", "no", 1].each do |value|
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
end
