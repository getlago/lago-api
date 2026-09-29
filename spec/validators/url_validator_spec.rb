# frozen_string_literal: true

require "rails_helper"

RSpec.describe UrlValidator do
  subject(:webhook_endpoint) { build(:webhook_endpoint, webhook_url:) }

  let(:webhook_url) { "https://hooks.example.com/lago" }
  let(:allow_private) { "false" }
  let(:resolved_address) { "93.184.215.14" }

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => allow_private))
    allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp(resolved_address, 0)])
  end

  context "when the url is not http" do
    let(:webhook_url) { "ftp://hooks.example.com" }

    it { is_expected.not_to be_valid }
  end

  context "when the host resolves to a public address" do
    it { is_expected.to be_valid }
  end

  context "when the host resolves to a private address" do
    let(:resolved_address) { "10.0.0.5" }

    it "adds an error" do
      webhook_endpoint.valid?

      expect(webhook_endpoint.errors.where(:webhook_url, :url_invalid)).to be_present
    end
  end

  context "when the host is a private IP literal" do
    let(:webhook_url) { "http://169.254.169.254/latest/meta-data" }

    before { allow(Addrinfo).to receive(:getaddrinfo).and_call_original }

    it { is_expected.not_to be_valid }
  end

  context "when the host does not resolve" do
    before { allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError) }

    it { is_expected.to be_valid }
  end

  context "when private addresses are allowed" do
    let(:allow_private) { "true" }
    let(:resolved_address) { "10.0.0.5" }

    it { is_expected.to be_valid }
  end

  context "when a persisted url now resolves to a private address" do
    subject(:webhook_endpoint) { create(:webhook_endpoint, webhook_url:) }

    before do
      webhook_endpoint
      allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp("10.0.0.5", 0)])
    end

    it "does not resolve the unchanged url again" do
      expect(webhook_endpoint).to be_valid
      expect(Addrinfo).to have_received(:getaddrinfo).with("hooks.example.com", nil, nil, :STREAM).once
    end
  end
end
