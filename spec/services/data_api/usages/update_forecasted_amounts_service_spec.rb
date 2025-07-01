# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::Usages::UpdateForecastedAmountsService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:params) do
    {usage_amounts: [{id: 1}, {id: 2}, {id: 3}, {id: 4}]}
  end

  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { "#{ENV["LAGO_DATA_API_URL"]}/usages/#{organization.id}/forecasted/amounts/" }
  let(:headers) { {"Authorization" => "Bearer #{ENV["LAGO_DATA_API_BEARER_TOKEN"]}"} }
  let(:response) { instance_double(Net::HTTPOK) }

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
    allow(lago_client).to receive(:put_with_response).with(params[:usage_amounts], headers).and_return(response)
  end

  describe "#call" do
    subject(:service_call) { service.call }

    context "when licence is not premium" do
      it "returns an error" do
        expect(service_call).not_to be_success
        expect(service_call.error.code).to eq("feature_unavailable")
      end
    end

    context "when licence is premium" do
      around { |test| lago_premium!(&test) }

      it "performs a PUT request and succeeds" do
        expect(service_call).to be_success
      end

      context "when the HTTP call raises an error" do
        let(:response) { instance_double(Net::HTTPOK) }

        before do
          allow(lago_client).to receive(:put_with_response).with(params[:usage_amounts], headers).and_raise(
            LagoHttpClient::HttpError.new("some_error", "Some error message", "")
          )
        end

        it "sets the result to service_failure with the error code and message" do
          expect(service_call).not_to be_success
          expect(service_call.error.code).to eq("some_error")
          expect(service_call.error.message).to eq("some_error: Some error message")
        end
      end
    end
  end

  describe "#action_path" do
    subject(:service_path) { service.send(:action_path) }

    it "returns the correct action path" do
      expect(subject).to eq("usages/#{organization.id}/forecasted/amounts/")
    end
  end
end
