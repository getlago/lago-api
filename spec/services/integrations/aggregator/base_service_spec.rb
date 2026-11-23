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
end
