# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::ValidateEmailService do
  subject(:result) { described_class.call(email:) }

  def errors_for(emails)
    emails.index_with { described_class.call(email: it).error&.messages }
  end

  context "with a company address" do
    let(:email) { "  Jane.Doe@GetLago.COM " }

    it "returns the canonical email, its domain and its mailbox key" do
      expect(result).to be_success
      expect(result.email).to eq("jane.doe@getlago.com")
      expect(result.domain).to eq("getlago.com")
      expect(result.mailbox_key).to eq("jane.doe@getlago.com")
    end
  end

  context "with a +tag" do
    let(:email) { "Jane+Signup@GetLago.com" }

    it "keeps the tag in the email and drops it from the mailbox key" do
      expect(result.email).to eq("jane+signup@getlago.com")
      expect(result.mailbox_key).to eq("jane@getlago.com")
    end
  end

  context "with a local part that starts with +" do
    let(:email) { "+tag@getlago.com" }

    it "keeps the whole local part in the mailbox key" do
      expect(result.mailbox_key).to eq("+tag@getlago.com")
    end
  end

  context "with a dash lookalike and an invisible character" do
    let(:email) { "jane–doe@get​lago.com" }

    it "normalizes them like the user lookup" do
      expect(result.email).to eq("jane-doe@getlago.com")
    end
  end

  context "with a decomposed Unicode local part" do
    let(:email) { "joão@getlago.com" }

    it "keeps its form in the email and composes it in the mailbox key" do
      expect(result.email).to eq("joão@getlago.com")
      expect(result.mailbox_key).to eq("joão@getlago.com")
    end
  end

  it "accepts subdomains, multi-label suffixes, punycode and Unicode local parts" do
    emails = %w[joão@getlago.com o'brien@getlago.com jane_doe-1+tag@getlago.com jane@eu.getlago.com jane@getlago.co.uk jane@xn--bcher-kva.de jane@xn--bcher-kva.xn--p1ai]

    expect(errors_for(emails)).to eq(emails.index_with { nil })
  end

  it "answers value_is_mandatory for a missing or blank email" do
    emails = [nil, "", "   ", "​"]

    expect(errors_for(emails)).to eq(emails.index_with { {email: ["value_is_mandatory"]} })
  end

  it "answers invalid_email_format for anything but one well-formed address" do
    emails = [
      "jane", "jane@", "@getlago.com", "jane@getlago", "jane@getlago.com.", "jane@.getlago.com", "jane@getlago..com",
      "a@getlago.com,b@getlago.com", "a@getlago.com b@getlago.com", "Jane <jane@getlago.com>",
      "\"jane,doe\"@getlago.com", "\"victim\"@acme.com", "jane@getlago.com\nbcc@example.org",
      "jane@[IPv6:2001:db8::1]", "jane@[1.2.3.x:a@b]", "jane@192.168.0.1", "jane@0x7f.0.0.1", "jane@getlago.c0m",
      "jane@gеtlago.com", "jane@bücher.de", "jane＠getlago.com", (+"jane\xFF@getlago.com").force_encoding("UTF-8"),
      "#{"a" * 65}@getlago.com", "jane@#{"a" * 64}.com", "#{"a" * 60}@#{"b" * 63}.#{"c" * 63}.#{"d" * 63}.com",
      "#{"a" * 513}@getlago.com", "=?utf-8?q?attacker=40evil.com=3e=00?=x@getlago.com", "jane%evil.com@getlago.com",
      "evil.com!jane@getlago.com", "jane=doe@getlago.com", "jane/doe@getlago.com"
    ]

    expect(errors_for(emails)).to eq(emails.index_with { {email: ["invalid_email_format"]} })
  end

  it "answers email_domain_not_allowed for personal, throwaway, literal and public-suffix domains" do
    emails = ["Jane@GMAIL.COM", "jane@gm​ail.com", "jane@abc.mailinator.com", "jane@[192.168.0.1]",
      "jane@[1.2.3.ipv6:abc]", "jane@co.uk", "jane@proton.me"]

    expect(errors_for(emails)).to eq(emails.index_with { {email: ["email_domain_not_allowed"]} })
  end

  context "with a refused address" do
    let(:email) { "jane@gmail.com" }

    it "returns no email or mailbox key" do
      expect(result.email).to be_nil
      expect(result.mailbox_key).to be_nil
    end
  end

  describe ".mailbox_key" do
    it "normalizes any string the same way, whether or not the policy accepts it" do
      expect(described_class.mailbox_key(" Jane+X@Gmail.com ")).to eq("jane@gmail.com")
      expect(described_class.mailbox_key("JANE@getlago.com")).to eq(described_class.call(email: "jane+a@getlago.com").mailbox_key)
      expect(described_class.mailbox_key("not-an-email")).to eq("not-an-email")
    end
  end
end
