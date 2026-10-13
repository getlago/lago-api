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
      expect(described_class.hit!(:login_failures_per_email, "user@example.com")).to be(false)
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

    it "does not block when the cache is unavailable" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

      expect(Array.new(5) { described_class.hit!(:password_reset_per_email, "user@example.com") }).to all(be(false))
    end

    it "does not store the identifier in clear" do
      expect(described_class.cache_key(:login_per_ip, "user@example.com")).not_to include("user@example.com")
    end
  end

  describe ".exceeded?" do
    it "returns true once the limit is reached, without counting" do
      9.times { described_class.hit!(:login_failures_per_email, "user@example.com") }
      expect(described_class.exceeded?(:login_failures_per_email, "user@example.com")).to be(false)

      described_class.hit!(:login_failures_per_email, "user@example.com")
      expect(described_class.exceeded?(:login_failures_per_email, "user@example.com")).to be(true)
    end
  end

  describe ".reset!" do
    it "clears the counter" do
      10.times { described_class.hit!(:login_failures_per_email, "user@example.com") }

      described_class.reset!(:login_failures_per_email, "user@example.com")

      expect(described_class.exceeded?(:login_failures_per_email, "user@example.com")).to be(false)
    end
  end
end
