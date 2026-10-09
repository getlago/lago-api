# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::DestroyService do
  subject(:result) { described_class.call(connection:) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }
  let(:connection) { create(:x402_connection, organization:) }

  describe "#call" do
    it "discards the connection" do
      expect { result }.to change { connection.reload.discarded? }.from(false).to(true)
    end

    it "keeps the row" do
      result

      expect(X402::Connection.with_discarded.exists?(connection.id)).to be(true)
    end

    it "returns the connection" do
      expect(result.connection).to eq(connection)
    end

    it "produces a security log" do
      result

      expect(security_logger).to have_received(:produce).with(
        organization:,
        log_type: "integration",
        log_event: "integration.deleted",
        resources: {integration_name: "Coinbase CDP", integration_type: "x402"}
      )
    end

    context "without a connection" do
      let(:connection) { nil }

      it "fails with a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("x402_connection_not_found")
      end
    end
  end
end
