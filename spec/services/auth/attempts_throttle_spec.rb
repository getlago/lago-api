# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::AttemptsThrottle do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { described_class.store = cache }

  describe ".hit!" do
    it "returns true once the limit is exceeded" do
      results = Array.new(4) { described_class.hit!(:password_reset_per_email, "user@example.com") }

      expect(results).to eq([false, false, false, true])
    end

    it "counts identifiers case-insensitively" do
      3.times { described_class.hit!(:password_reset_per_email, "User@Example.com ") }

      expect(described_class.hit!(:password_reset_per_email, "user@example.com")).to be(true)
    end

    it "counts email spelling variants that resolve to the same user together" do
      variants = ["jane\u2013doe@example.com", "jane-d\u200Boe@example.com", "\uFEFFjane\u2212doe@example.com"]

      expect(variants.map { User.normalize_value_for(:email, it) }.uniq).to eq(["jane-doe@example.com"])

      variants.each { described_class.hit!(:password_reset_per_email, it) }

      expect(described_class.hit!(:password_reset_per_email, "jane-doe@example.com")).to be(true)
    end

    it "counts the Unicode spellings of one address together" do
      ["jo\u00E3o@example.com", "Joa\u0303o@example.com", "JO\u00C3O@example.com"].each { described_class.hit!(:password_reset_per_email, it) }

      expect(described_class.hit!(:password_reset_per_email, "joa\u0303o@example.com")).to be(true)
    end

    it "keeps rules and identifiers separate" do
      3.times { described_class.hit!(:password_reset_per_email, "user@example.com") }

      expect(described_class.hit!(:password_reset_per_email, "other@example.com")).to be(false)
      expect(described_class.hit!(:login_per_email, "user@example.com")).to be(false)
    end

    it "resets after the period" do
      3.times { described_class.hit!(:password_reset_per_email, "user@example.com") }

      travel_to(61.minutes.from_now) do
        expect(described_class.hit!(:password_reset_per_email, "user@example.com")).to be(false)
      end
    end

    it "ignores a blank identifier" do
      expect(Array.new(5) { described_class.hit!(:password_reset_per_email, nil) }).to all(be(false))
    end

    it "counts a rule keyed on the email and IP pair per pair" do
      10.times { described_class.hit!(:login_per_email_and_ip, "User@Example.com", "203.0.113.10") }

      expect(described_class.hit!(:login_per_email_and_ip, "user@example.com", "203.0.113.11")).to be(false)
      expect(described_class.hit!(:login_per_email_and_ip, "user@example.com", "203.0.113.10")).to be(true)
    end

    it "ignores a pair with a blank part" do
      results = Array.new(11) { described_class.hit!(:login_per_email_and_ip, "user@example.com", nil) }

      expect(results).to all(be(false))
    end

    it "raises when the identifiers do not match the rule" do
      expect { described_class.hit!(:login_per_email_and_ip, "user@example.com") }.to raise_error(ArgumentError)
    end

    context "when the cache is unavailable" do
      let(:cache) { ActiveSupport::Cache::NullStore.new }

      it "does not block" do
        expect(Array.new(5) { described_class.hit!(:password_reset_per_email, "user@example.com") }).to all(be(false))
      end
    end

    it "does not store the identifier in clear" do
      expect(described_class.cache_key(:login_per_ip, "user@example.com")).not_to include("user@example.com")
    end

    context "with a rule keyed on the client network" do
      it "counts the IPv6 addresses of one /64 together, and other /64s apart" do
        10.times { described_class.hit!(:signup_per_ip, "2001:db8:1:2::a") }

        expect(described_class.hit!(:signup_per_ip, "2001:db8:1:3::a")).to be(false)
        expect(described_class.hit!(:signup_per_ip, "2001:db8:1:2::b")).to be(true)
      end

      it "counts IPv4 per address, and an IPv4-mapped IPv6 address as its IPv4" do
        10.times { described_class.hit!(:signup_per_ip, "203.0.113.10") }

        expect(described_class.hit!(:signup_per_ip, "203.0.113.11")).to be(false)
        expect(described_class.hit!(:signup_per_ip, "::ffff:203.0.113.10")).to be(true)
      end

      it "counts an unparsable identifier by its value" do
        10.times { described_class.hit!(:signup_per_ip, "not-an-ip") }

        expect(described_class.hit!(:signup_per_ip, "Not-An-IP ")).to be(true)
      end
    end

    context "with a rule keyed on the client block" do
      it "counts the IPv6 addresses of one /48 together, and IPv4 per address" do
        50.times { described_class.hit!(:signup_per_ip_block, "2001:db8:1:2::a") }

        expect(described_class.hit!(:signup_per_ip_block, "2001:db8:2::a")).to be(false)
        expect(described_class.hit!(:signup_per_ip_block, "2001:db8:1:ff::a")).to be(true)

        50.times { described_class.hit!(:signup_per_ip_block, "203.0.113.10") }
        expect(described_class.hit!(:signup_per_ip_block, "203.0.113.11")).to be(false)
      end
    end

    it "counts self-serve login attempts per IPv6 /64 and per IPv4 address" do
      30.times { described_class.hit!(:login_per_ip_network, "2001:db8:1:2::#{(it + 1).to_s(16)}") }

      expect(described_class.hit!(:login_per_ip_network, "2001:db8:1:2::ffff")).to be(true)
      expect(described_class.hit!(:login_per_ip_network, "2001:db8:1:3::a")).to be(false)

      30.times { described_class.hit!(:login_per_ip_network, "203.0.113.10") }
      expect(described_class.hit!(:login_per_ip_network, "203.0.113.11")).to be(false)
    end

    it "still counts IPv6 per address for a rule keyed on the IP" do
      30.times { described_class.hit!(:login_per_ip, "2001:db8:1:2::a") }

      expect(described_class.hit!(:login_per_ip, "2001:db8:1:2::b")).to be(false)
    end

    it "counts signup emails per mailbox key" do
      mailbox_key = Signups::ValidateEmailService.mailbox_key("jane+1@acme.com")

      3.times { described_class.hit!(:signup_email_per_hour, Signups::ValidateEmailService.mailbox_key("Jane+#{it}@Acme.com")) }

      expect(described_class.hit!(:signup_email_per_hour, Signups::ValidateEmailService.mailbox_key("j.ane@acme.com"))).to be(false)
      expect(described_class.hit!(:signup_email_per_hour, mailbox_key)).to be(true)
    end
  end

  it "keys every signup rule on a client network, a client block or an email, never on a raw IP" do
    signup_rules = described_class::RULES.select { |name, _| name.start_with?("signup_") }

    expect(signup_rules.values.map(&:identifier).uniq).to match_array(%i[ip_network ip_block email])
  end

  describe ".at_limit?" do
    it "answers whether one more attempt would go over the limit, without recording one" do
      9.times { described_class.hit!(:signup_per_ip, "203.0.113.10") }
      expect(described_class.at_limit?(:signup_per_ip, "203.0.113.10")).to be(false)

      described_class.hit!(:signup_per_ip, "203.0.113.10")
      expect(Array.new(2) { described_class.at_limit?(:signup_per_ip, "203.0.113.10") }).to eq([true, true])
      expect(described_class.hit!(:signup_per_ip, "203.0.113.10")).to be(true)
    end

    it "answers false for a blank identifier" do
      expect(described_class.at_limit?(:signup_per_ip, nil)).to be(false)
    end
  end

  describe ".first_in_period?" do
    it "answers true once per name and period" do
      expect(Array.new(2) { described_class.first_in_period?("alert", 10.minutes) }).to eq([true, false])
      expect(described_class.first_in_period?("other_alert", 10.minutes)).to be(true)

      travel_to(11.minutes.from_now) { expect(described_class.first_in_period?("alert", 10.minutes)).to be(true) }
    end

    context "when the store fails" do
      before { allow(cache).to receive(:write).and_return(nil) }

      it "answers true, so an alert is never silenced by an outage" do
        expect(Array.new(2) { described_class.first_in_period?("alert", 10.minutes) }).to eq([true, true])
      end
    end
  end

  describe ".reset!" do
    it "clears the counter" do
      10.times { described_class.hit!(:login_per_email, "user@example.com") }

      described_class.reset!(:login_per_email, "user@example.com")

      expect(described_class.hit!(:login_per_email, "user@example.com")).to be(false)
    end
  end

  describe ".store" do
    before { described_class.store = nil }

    it "defaults to the throttling Redis" do
      expect(described_class.store).to be(described_class::DEFAULT_STORE.value)
    end
  end
end
