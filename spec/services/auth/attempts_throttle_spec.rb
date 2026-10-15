# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::AttemptsThrottle do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

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
  end

  describe ".reset!" do
    it "clears the counter" do
      10.times { described_class.hit!(:login_per_email, "user@example.com") }

      described_class.reset!(:login_per_email, "user@example.com")

      expect(described_class.hit!(:login_per_email, "user@example.com")).to be(false)
    end
  end

  describe ".store" do
    it "uses Rails.cache when it is shared" do
      expect(described_class.store).to be(cache)
    end

    context "when Rails.cache is a per-process file store" do
      let(:cache) { ActiveSupport::Cache::FileStore.new(Dir.mktmpdir) }

      it "falls back to the Sidekiq Redis" do
        expect(described_class.store).to be(described_class::FALLBACK_STORE.value)
      end
    end

    context "when a dedicated throttling Redis is configured" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_REDIS_THROTTLING_URL" => "redis://throttling:6379")) }

      it "uses it instead of Rails.cache" do
        expect(described_class.store).to be(described_class::THROTTLING_STORE.value)
      end
    end
  end
end
