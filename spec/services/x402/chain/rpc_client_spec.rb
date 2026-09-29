# frozen_string_literal: true

require "rails_helper"

describe X402::Chain::RpcClient do
  subject(:client) { described_class.new(network:) }

  let(:network) { "eip155:84532" }
  let(:rpc_urls) { nil }

  before { stub_const("ENV", ENV.to_h.merge("LAGO_X402_RPC_URLS" => rpc_urls)) }

  describe "#url" do
    {
      "eip155:8453" => "https://mainnet.base.org",
      "eip155:84532" => "https://sepolia.base.org",
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => "https://api.mainnet-beta.solana.com",
      "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => "https://api.devnet.solana.com"
    }.each do |default_network, default_url|
      context "with #{default_network}" do
        let(:network) { default_network }

        it "defaults to the public endpoint" do
          expect(client.url).to eq(default_url)
        end
      end
    end

    context "when LAGO_X402_RPC_URLS overrides a network" do
      let(:rpc_urls) { {"eip155:84532" => "https://base-sepolia.example.com/v2/key"}.to_json }

      it "uses the configured endpoint" do
        expect(client.url).to eq("https://base-sepolia.example.com/v2/key")
      end

      it "keeps the defaults of the other networks" do
        expect(described_class.new(network: "eip155:8453").url).to eq("https://mainnet.base.org")
      end
    end

    context "when LAGO_X402_RPC_URLS is not JSON" do
      let(:rpc_urls) { "eip155:84532=https://example.com" }

      it "raises" do
        expect { client }.to raise_error(ArgumentError, /LAGO_X402_RPC_URLS/)
      end
    end

    context "when LAGO_X402_RPC_URLS is not an object of URLs" do
      let(:rpc_urls) { ["https://example.com"].to_json }

      it "raises" do
        expect { client }.to raise_error(ArgumentError, /LAGO_X402_RPC_URLS/)
      end
    end

    context "when a configured URL is malformed" do
      let(:rpc_urls) { {"eip155:84532" => "https://rpc.example.com/v2/SECRETKEY\n"}.to_json }

      it "raises without the URL" do
        expect { client }.to raise_error(ArgumentError) { |error| expect(error.message).not_to include("SECRETKEY") }
      end
    end

    context "when a configured URL is not http" do
      let(:rpc_urls) { {"eip155:84532" => "ftp://rpc.example.com/SECRETKEY"}.to_json }

      it "raises without the URL" do
        expect { client }.to raise_error(ArgumentError) { |error| expect(error.message).not_to include("SECRETKEY") }
      end
    end

    context "when the malformed JSON quotes a key" do
      let(:rpc_urls) { "{'eip155:84532':'https://rpc.example.com/v2/SECRETKEY'}" }

      it "drops the parser's cause, which quotes the value" do
        expect { client }.to raise_error(ArgumentError) { |error| expect([error.message.include?("SECRETKEY"), error.cause]).to eq([false, nil]) }
      end
    end

    context "with a network that has no endpoint" do
      let(:network) { "eip155:1" }

      it "raises" do
        expect { client }.to raise_error(ArgumentError, /no RPC endpoint/)
      end
    end
  end

  describe "#call" do
    subject(:call) { client.call("eth_blockNumber", []) }

    let(:url) { "https://sepolia.base.org" }

    context "when the endpoint answers" do
      before { stub_request(:post, url).with(body: {jsonrpc: "2.0", id: 1, method: "eth_blockNumber", params: []}.to_json).to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: "0x2d40e01"}.to_json) }

      it { is_expected.to eq("0x2d40e01") }
    end

    context "when the result is null" do
      before { stub_request(:post, url).to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: nil}.to_json) }

      it { is_expected.to be_nil }
    end

    context "when the endpoint answers without a result" do
      before { stub_request(:post, url).to_return(status: 200, body: {jsonrpc: "2.0", id: 1}.to_json) }

      it "raises" do
        expect { call }.to raise_error(X402::Chain::UnreachableError, "eth_blockNumber: no result")
      end
    end

    context "when the endpoint answers a JSON-RPC error" do
      before { stub_request(:post, url).to_return(status: 200, body: {jsonrpc: "2.0", id: 1, error: {code: -32614, message: "eth_getLogs is limited to a 1,000 range"}}.to_json) }

      it "raises with the endpoint's message" do
        expect { call }.to raise_error(X402::Chain::UnreachableError, "eth_blockNumber: eth_getLogs is limited to a 1,000 range")
      end
    end

    context "when the endpoint answers something other than JSON" do
      before { stub_request(:post, url).to_return(status: 200, body: "<html>rate limited</html>") }

      it "raises" do
        expect { call }.to raise_error(X402::Chain::UnreachableError, "eth_blockNumber: JSON::ParserError")
      end
    end

    context "when a keyed endpoint fails" do
      let(:rpc_urls) { {"eip155:84532" => "https://rpc.example.com/v2/secret-key"}.to_json }

      before { stub_request(:post, "https://rpc.example.com/v2/secret-key").to_return(status: 503, body: "Service Unavailable https://rpc.example.com/v2/secret-key") }

      it "raises without the URL" do
        expect { call }.to raise_error(X402::Chain::UnreachableError, "eth_blockNumber: HTTP 503")
      end

      it "drops the cause, which carries the URL" do
        expect { call }.to raise_error { |error| expect(error.cause).to be_nil }
      end
    end

    [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED, SocketError].each do |transport_error|
      context "when the connection fails with #{transport_error}" do
        before { stub_request(:post, url).to_raise(transport_error) }

        it "raises" do
          expect { call }.to raise_error(X402::Chain::UnreachableError, "eth_blockNumber: #{transport_error}")
        end
      end
    end
  end
end
