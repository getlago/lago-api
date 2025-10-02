# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoHttpClient::Client do
  subject(:client) { described_class.new(url) }

  let(:url) { "http://example.com/api/v1/example" }

  describe "#initialize" do
    it "use default timeouts from Net::HTTP" do
      expect(client.send(:http_client).write_timeout).to eq 60
      expect(client.send(:http_client).read_timeout).to eq 60
    end

    it "can override timeouts" do
      client = described_class.new(url, read_timeout: 8, write_timeout: 12)
      expect(client.send(:http_client).write_timeout).to eq 12
      expect(client.send(:http_client).read_timeout).to eq 8
    end
  end

  describe "#post" do
    context "when response status code is 2xx" do
      let(:response) do
        {
          "status" => 200,
          "message" => "Success"
        }.to_json
      end

      before do
        stub_request(:post, "http://example.com/api/v1/example")
          .to_return(body: response, status: 200)
      end

      it "returns response body" do
        response = client.post("", {})

        expect(response["status"]).to eq 200
        expect(response["message"]).to eq "Success"
      end

      context "when response body is blank" do
        let(:response) { "" }

        it "returns an empty response" do
          response = client.post("", {})

          expect(response).to eq({})
        end
      end

      context "when response is not a JSON" do
        let(:response) { "Accepted" }

        it "returns response body" do
          response = client.post("", {})

          expect(response).to eq("Accepted")
        end
      end
    end

    context "when response status code is NOT 2xx" do
      let(:response) do
        {
          "status" => 422,
          "error" => "Unprocessable Entity",
          "message" => "Validation error on the record"
        }.to_json
      end

      before do
        stub_request(:post, "http://example.com/api/v1/example")
          .to_return(body: response, status: 422)
      end

      it "raises an error" do
        expect { client.post("", {}) }.to raise_error LagoHttpClient::HttpError
      end
    end

    context "when path is empty" do
      let(:url) { "http://example.com" }

      let(:response) do
        {
          "status" => 200,
          "message" => "Success"
        }.to_json
      end

      before do
        stub_request(:post, "http://example.com/")
          .to_return(body: response, status: 200)
      end

      it "returns response body" do
        response = client.post("", {})

        expect(response["status"]).to eq 200
        expect(response["message"]).to eq "Success"
      end
    end

    context "with query params" do
      let(:url) { "http://example.com/api?foo=bar" }

      let(:response) do
        {
          "status" => 200,
          "message" => "Success"
        }.to_json
      end

      before do
        stub_request(:post, "http://example.com/api?foo=bar")
          .to_return(body: response, status: 200)
      end

      it "returns response body" do
        response = client.post("", {})

        expect(response["status"]).to eq 200
        expect(response["message"]).to eq "Success"
      end
    end
  end
end
