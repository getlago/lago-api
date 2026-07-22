# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinanceAssistant::ExportService do
  subject(:result) { described_class.call(organization:, message_id:) }

  let(:organization) { create(:organization) }
  let(:message_id) { SecureRandom.uuid }
  let(:finance_assistant_url) { "http://finance-assistant.test" }

  around do |example|
    previous_url = ENV["LAGO_FINANCE_ASSISTANT_URL"]
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = finance_assistant_url
    example.run
    ENV["LAGO_FINANCE_ASSISTANT_URL"] = previous_url
  end

  context "when the agent returns a CSV" do
    before do
      stub_request(:post, "#{finance_assistant_url}/export")
        .with(
          body: {message_id:},
          headers: {"X-Organization-Id" => organization.id}
        )
        .to_return(
          status: 200,
          body: {
            content: "id,name\n1,alice\n",
            filename: "finance-assistant-#{message_id}.csv",
            row_count: 1,
            truncated: false
          }.to_json
        )
    end

    it "uploads the CSV as a blob and returns a signed download url" do
      expect { result }.to change(ActiveStorage::Blob, :count).by(1)

      expect(result).to be_success
      expect(result.export[:file_url]).to be_present
      expect(result.export[:filename]).to end_with("_finance_export.csv")

      blob = ActiveStorage::Blob.last
      expect(blob.content_type).to eq("text/csv")
      expect(blob.download).to eq("id,name\n1,alice\n")
    end
  end

  context "without finance assistant URL" do
    before { ENV["LAGO_FINANCE_ASSISTANT_URL"] = nil }

    it "returns a forbidden failure and uploads nothing" do
      expect { result }.not_to change(ActiveStorage::Blob, :count)
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("feature_unavailable")
    end
  end

  context "when the stored result has aged out (410 export_expired)" do
    before do
      stub_request(:post, "#{finance_assistant_url}/export")
        .to_return(status: 410, body: {detail: "export_expired"}.to_json)
    end

    it "returns a service failure and uploads nothing" do
      expect { result }.not_to change(ActiveStorage::Blob, :count)
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("export_expired")
    end
  end

  context "when the query cannot be re-run (422 export_unavailable)" do
    before do
      stub_request(:post, "#{finance_assistant_url}/export")
        .to_return(status: 422, body: {detail: "export_unavailable"}.to_json)
    end

    it "returns a service failure carrying the export_unavailable code" do
      expect(result).to be_failure
      expect(result.error.code).to eq("export_unavailable")
    end
  end

  context "when the finance assistant returns a malformed success response" do
    before do
      stub_request(:post, "#{finance_assistant_url}/export")
        .to_return(status: 200, body: {content: "id\n1\n"}.to_json)
    end

    it "returns an invalid response failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("finance_assistant_invalid_response")
    end
  end
end
