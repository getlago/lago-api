# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::BaseService do
  let(:service) { described_class.new(integration:) }
  let(:integration) { create(:netsuite_integration) }

  describe "#request_limit_error?" do
    subject(:service_call) { service.__send__(:request_limit_error?, http_error) }

    let(:http_error) { instance_double("LagoHttpClient::Error", error_code: error_code, error_body: error_body) }

    context "when error code is 500" do
      let(:error_code) { 500 }

      context "when error body includes request limit error code" do
        let(:error_body) { 'Some error message including SSS_REQUEST_LIMIT_EXCEEDED' }

        it "returns true" do
          expect(service_call).to be true
        end
      end

      context "when error body does not include request limit error code" do
        let(:error_body) { 'Some other error message' }

        it "returns false" do
          expect(service_call).to be false
        end
      end
    end

    context "when error code is 424" do
      let(:error_code) { 424 }

      context "when error body includes request limit error code" do
        let(:error_body) { 'Some error message including SSS_REQUEST_LIMIT_EXCEEDED' }

        it "returns true" do
          expect(service_call).to be true
        end
      end

      context "when error body does not include request limit error code" do
        let(:error_body) { 'Some other error message' }

        it "returns false" do
          expect(service_call).to be false
        end
      end
    end

    context "when error code is not 500 or 424" do
      let(:error_code) { 400 }
      let(:error_body) { 'Some error message including SSS_REQUEST_LIMIT_EXCEEDED' }

      it "returns false" do
        expect(service_call).to be false
      end
    end
  end
end
