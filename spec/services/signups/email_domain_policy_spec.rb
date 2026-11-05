# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::EmailDomainPolicy do
  describe ".refusal_reason" do
    context "with the bundled lists" do
      it "refuses the free providers, disposable domains and private relays" do
        domains = %w[gmail.com outlook.com yahoo.com icloud.com proton.me pm.me protonmail.com fastmail.com
          user.fastmail.com mailinator.com abc.mailinator.com privaterelay.appleid.com mozmail.com
          outlook.fr hotmail.be yahoo.dk posteo.de protonmail.ch]

        expect(domains.index_with { described_class.refusal_reason(it) }).to eq(
          "gmail.com" => :free_provider,
          "outlook.com" => :free_provider,
          "yahoo.com" => :free_provider,
          "icloud.com" => :free_provider,
          "proton.me" => :denied,
          "outlook.fr" => :denied,
          "hotmail.be" => :denied,
          "yahoo.dk" => :denied,
          "posteo.de" => :denied,
          "protonmail.ch" => :denied,
          "pm.me" => :free_provider,
          "protonmail.com" => :free_provider,
          "fastmail.com" => :free_provider,
          "user.fastmail.com" => :free_provider,
          "mailinator.com" => :disposable,
          "abc.mailinator.com" => :disposable,
          "privaterelay.appleid.com" => :private_relay,
          "mozmail.com" => :private_relay
        )
      end

      it "refuses every entry of signup_email_domains.yaml as denied" do
        domains = described_class::DENIED_DOMAINS

        expect(domains.index_with { described_class.refusal_reason(it) }).to eq(domains.index_with { :denied })
      end

      it "accepts company domains, including under multi-label suffixes" do
        domains = %w[getlago.com eu.getlago.com bbc.co.uk abc.net.au stripe.com]

        expect(domains.index_with { described_class.refusal_reason(it) }).to eq(domains.index_with { nil })
      end
    end
  end

  describe ".default" do
    it "builds the policy once" do
      policy = described_class.default

      expect(described_class.default).to be(policy)
    end
  end

  describe "#refusal_reason" do
    subject(:policy) { described_class.new(free:, disposable:, private_relays:, allowed:, denied:) }

    let(:free) { Set["gmail.com", "fastmail.com"] }
    let(:disposable) { Set["mailinator.com", "com", "co.uk"] }
    let(:private_relays) { Set["mozmail.com"] }
    let(:allowed) { Set[] }
    let(:denied) { Set[] }

    it "matches each list on the domain and its parents, whatever the case" do
      domains = %w[gmail.com mail.gmail.com alias.user.fastmail.com GMAIL.COM a.b.mailinator.com alias.mozmail.com]

      expect(domains.index_with { policy.refusal_reason(it) }).to eq(
        "gmail.com" => :free_provider,
        "mail.gmail.com" => :free_provider,
        "alias.user.fastmail.com" => :free_provider,
        "GMAIL.COM" => :free_provider,
        "a.b.mailinator.com" => :disposable,
        "alias.mozmail.com" => :private_relay
      )
    end

    it "never matches a public suffix entry" do
      expect(policy.refusal_reason("acme.com")).to be_nil
      expect(policy.refusal_reason("acme.co.uk")).to be_nil
    end

    it "refuses a domain that is itself a public suffix" do
      expect(policy.refusal_reason("co.uk")).to eq(:public_suffix)
    end

    it "refuses address literals" do
      expect(policy.refusal_reason("[10.0.0.1]")).to eq(:ip_literal)
      expect(policy.refusal_reason("[1.2.3.ipv6:abc]")).to eq(:ip_literal)
    end

    it "raises on an email address or a non-domain, without echoing the input" do
      ["jane@gmail.com", "1.2.3.4", "0x7f.0.0.1", "gmail"].each do |input|
        expect { policy.refusal_reason(input) }.to raise_error(ArgumentError) { |error| expect(error.message).not_to include(input) }
      end
    end

    context "with an allowed domain that a list marks" do
      let(:allowed) { Set["acme.com"] }
      let(:disposable) { Set["acme.com"] }

      it "accepts it and its subdomains" do
        expect(policy.refusal_reason("acme.com")).to be_nil
        expect(policy.refusal_reason("eu.acme.com")).to be_nil
      end
    end

    context "with a denied domain" do
      let(:denied) { Set["throwaway.io"] }

      it "refuses it and its subdomains" do
        expect(policy.refusal_reason("x.throwaway.io")).to eq(:denied)
      end

      context "when it is also allowed" do
        let(:allowed) { Set["throwaway.io"] }

        it "accepts it" do
          expect(policy.refusal_reason("throwaway.io")).to be_nil
        end
      end
    end

    context "with allowed entries for a literal or a public suffix" do
      let(:allowed) { Set["co.uk"] }

      it "still refuses them" do
        expect(policy.refusal_reason("[10.0.0.1]")).to eq(:ip_literal)
        expect(policy.refusal_reason("co.uk")).to eq(:public_suffix)
      end
    end
  end

  describe ".parse_domains" do
    it "returns a frozen set of downcased, stripped entries" do
      expect(described_class.parse_domains(nil, source: "X")).to eq(Set[]).and be_frozen
      expect(described_class.parse_domains("", source: "X")).to eq(Set[])
      expect(described_class.parse_domains(" Acme.com, ,beta.io ", source: "X")).to eq(Set["acme.com", "beta.io"]).and be_frozen
      expect(described_class.parse_domains(["Acme.com"], source: "X")).to eq(Set["acme.com"])
    end

    it "raises on an entry that is not a domain name, naming the source" do
      ["acme", "http://acme.com", "jane@acme.com", "1.2.3.4", "acme..com"].each do |entry|
        expect { described_class.parse_domains(entry, source: "MY_SOURCE") }.to raise_error(ArgumentError, /MY_SOURCE/)
      end
    end
  end
end
