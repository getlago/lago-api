# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoHttpClient::AddressGuard do
  describe ".enabled?" do
    subject(:enabled) { described_class.enabled? }

    before { stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => allow_private)) }

    context "without the allow flag" do
      let(:allow_private) { nil }

      it { is_expected.to be(true) }
    end

    context "with the allow flag set to false" do
      let(:allow_private) { "false" }

      it { is_expected.to be(true) }
    end

    context "with the allow flag set to true" do
      let(:allow_private) { "true" }

      it { is_expected.to be(false) }
    end
  end

  describe ".blocked_ip?" do
    [
      "0.0.0.0",
      "10.1.2.3",
      "100.64.0.1",
      "127.0.0.1",
      "169.254.169.254",
      "172.16.0.1",
      "172.31.255.255",
      "192.0.0.1",
      "192.168.1.1",
      "198.18.0.1",
      "224.0.0.1",
      "255.255.255.255",
      "::",
      "::1",
      "::ffff:127.0.0.1",
      "::ffff:169.254.169.254",
      "2002:7f00:1::",
      "fc00::1",
      "fd00:ec2::254",
      "fe80::1",
      "ff02::1"
    ].each do |address|
      it "blocks #{address}" do
        expect(described_class.blocked_ip?(address)).to be(true)
      end
    end

    %w[8.8.8.8 93.184.215.14 172.32.0.1 2606:4700:4700::1111].each do |address|
      it "allows #{address}" do
        expect(described_class.blocked_ip?(address)).to be(false)
      end
    end
  end

  describe ".resolve!" do
    subject(:resolve) { described_class.resolve!("hooks.example.com") }

    before do
      allow(Addrinfo).to receive(:getaddrinfo)
        .with("hooks.example.com", nil, nil, :STREAM)
        .and_return(addresses.map { |address| Addrinfo.tcp(address, 0) })
    end

    context "when every address is public" do
      let(:addresses) { %w[93.184.215.14 2606:2800:21f:cb07:6820:80da:af6b:8b2c] }

      it "returns the first address" do
        expect(resolve).to eq("93.184.215.14")
      end
    end

    context "when one of the addresses is private" do
      let(:addresses) { %w[93.184.215.14 10.0.0.5] }

      it "raises a blocked address error" do
        expect { resolve }.to raise_error(LagoHttpClient::BlockedAddressError)
      end
    end

    context "when the host resolves to an IPv6 loopback" do
      let(:addresses) { %w[::1] }

      it "raises a blocked address error" do
        expect { resolve }.to raise_error(LagoHttpClient::BlockedAddressError)
      end
    end

    context "when the host resolves to nothing" do
      let(:addresses) { [] }

      it "raises a socket error" do
        expect { resolve }.to raise_error(SocketError)
      end
    end
  end
end
