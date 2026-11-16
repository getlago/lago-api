# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoUtils::License do
  subject(:license) { described_class.new(url) }

  let(:url) { "https://license.lago" }

  before do
    ENV["LAGO_LICENSE"] = "test-license"
  end

  describe "#verify" do
    context "when license is valid" do
      let(:response) do
        {
          "valid" => true
        }.to_json
      end

      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_return(body: response, status: 200)
      end

      it "sets premium to true" do
        license.verify

        expect(license).to be_premium
      end
    end

    context "when license is not present" do
      before do
        ENV["LAGO_LICENSE"] = nil
      end

      it "keeps premium to false" do
        license.verify

        expect(license).not_to be_premium
      end
    end

    context "when DNS resolution fails once" do
      before do
        call_count = 0
        stub_request(:get, "#{url}/verify/test-license").to_return do
          call_count += 1
          raise Socket::ResolutionError, "getaddrinfo: Temporary failure in name resolution" if call_count == 1
          {body: {"valid" => true}.to_json, status: 200}
        end
      end

      it "retries and sets premium to true" do
        license.verify

        expect(license).to be_premium
      end
    end

    context "when the license server answers 503 once" do
      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_return({status: 503}, {body: {"valid" => true}.to_json, status: 200})
      end

      it "retries and sets premium to true" do
        license.verify

        expect(license).to be_premium
      end
    end

    context "when DNS resolution keeps failing" do
      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_raise(Socket::ResolutionError.new("getaddrinfo: Temporary failure in name resolution"))
      end

      it "raises after the last attempt" do
        expect { license.verify }.to raise_error(Socket::ResolutionError)
        expect(a_request(:get, "#{url}/verify/test-license")).to have_been_made.times(3)
      end
    end

    context "when license is invalid" do
      let(:response) do
        {
          "valid" => false
        }.to_json
      end

      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_return(body: response, status: 200)
      end

      it "keeps premium to false" do
        license.verify

        expect(license).not_to be_premium
      end
    end
  end
end
