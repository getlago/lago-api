# frozen_string_literal: true

require "rails_helper"
require "lago/diagnostics"

RSpec.describe Lago::Diagnostics do
  subject(:diagnostics) { described_class.new(output:) }

  let(:output) { StringIO.new }
  let(:report) do
    diagnostics.call
    output.string
  end

  describe "#call" do
    before do
      allow(Clickhouse::BaseRecord).to receive(:connection)
        .and_raise(StandardError, "clickhouse unavailable in specs")
      allow(Clickhouse::BaseRecord).to receive(:connection_pool)
        .and_raise(StandardError, "clickhouse unavailable in specs")
    end

    it_behaves_like "a lago diagnostics report"

    context "when masking one environment variable raises" do
      let(:instance) { described_class.new(output:) }

      before do
        ENV["LAGO_SUPPORT_INFO_SPEC_BROKEN"] = "broken-value"
        ENV["LAGO_SUPPORT_INFO_SPEC_PLAIN"] = "plain-value"
        allow(instance).to receive(:mask).and_call_original
        allow(instance).to receive(:mask)
          .with("LAGO_SUPPORT_INFO_SPEC_BROKEN", "broken-value")
          .and_raise(StandardError, "bad entry")
      end

      after do
        ENV.delete("LAGO_SUPPORT_INFO_SPEC_BROKEN")
        ENV.delete("LAGO_SUPPORT_INFO_SPEC_PLAIN")
      end

      it "prints an error marker for that entry and keeps dumping the others" do
        instance.call

        expect(output.string).to include("error: StandardError - bad entry")
        expect(output.string).not_to include("broken-value")
        expect(output.string).to include("LAGO_SUPPORT_INFO_SPEC_PLAIN=plain-value")
        expect(output.string).to include("END OF DIAGNOSTIC")
      end
    end
  end

  describe "#mask" do
    it "masks values of secret-matching keys" do
      expect(diagnostics.mask("LAGO_SMTP_PASSWORD", "hunter2")).to eq("***")
      expect(diagnostics.mask("SECRET_KEY_BASE", "abc123")).to eq("***")
      expect(diagnostics.mask("LAGO_DATA_API_BEARER_TOKEN", "abc123")).to eq("***")
    end

    it "masks values of client_id and license keys" do
      expect(diagnostics.mask("GOCARDLESS_CLIENT_ID", "OJWZfIzwIwf5Ww6W")).to eq("***")
      expect(diagnostics.mask("LAGO_LICENSE", "lic-123")).to eq("***")
    end

    it "masks values of passphrase, signature and cert keys" do
      expect(diagnostics.mask("SSL_PASSPHRASE", "hunter2")).to eq("***")
      expect(diagnostics.mask("LAGO_WEBHOOK_SIGNATURE", "sig-123")).to eq("***")
      expect(diagnostics.mask("LAGO_TLS_CERT", "-----BEGIN-----")).to eq("***")
    end

    it "redacts URL userinfo credentials while keeping host and port visible" do
      expect(diagnostics.mask("DATABASE_URL", "postgresql://lago:changeme@db:5432/lago"))
        .to eq("postgresql://***@db:5432/lago")
      expect(diagnostics.mask("REDIS_URL", "redis://user@redis:6379"))
        .to eq("redis://***@redis:6379")
    end

    it "redacts the whole userinfo when the password contains an @" do
      expect(diagnostics.mask("DATABASE_URL", "postgresql://user:p@ss@db:5432/lago"))
        .to eq("postgresql://***@db:5432/lago")
    end

    it "redacts userinfo credentials in front of an IPv6 host" do
      expect(diagnostics.mask("REDIS_URL", "redis://user:pass@[::1]:6379"))
        .to eq("redis://***@[::1]:6379")
    end

    it "keeps URL values without userinfo untouched" do
      expect(diagnostics.mask("LAGO_API_URL", "http://localhost:3000"))
        .to eq("http://localhost:3000")
      expect(diagnostics.mask("DATABASE_URL", "postgresql://db:5432/lago"))
        .to eq("postgresql://db:5432/lago")
    end

    it "redacts sensitive query string parameters" do
      expect(diagnostics.mask("DATABASE_URL", "postgresql://lago@db/lago?password=secret123"))
        .to eq("postgresql://***@db/lago?password=***")
      expect(diagnostics.mask("REDIS_URL", "redis://redis:6379/0?user=lago&access_token=abc123"))
        .to eq("redis://redis:6379/0?user=lago&access_token=***")
    end

    it "redacts query parameters whose name tokens match a secret keyword" do
      expect(diagnostics.mask("SOME_URL", "http://h?password=x")).to eq("http://h?password=***")
      expect(diagnostics.mask("SOME_URL", "http://h?passwd=x")).to eq("http://h?passwd=***")
      expect(diagnostics.mask("SOME_URL", "http://h?pass=x")).to eq("http://h?pass=***")
      expect(diagnostics.mask("SOME_URL", "http://h?salt=x")).to eq("http://h?salt=***")
      expect(diagnostics.mask("SOME_URL", "http://h?a=b&access_token=x")).to eq("http://h?a=b&access_token=***")
      expect(diagnostics.mask("SOME_URL", "http://h?sslkey=x")).to eq("http://h?sslkey=***")
      expect(diagnostics.mask("SOME_URL", "http://h?api_key=x")).to eq("http://h?api_key=***")
      expect(diagnostics.mask("SOME_URL", "http://h?oauth_token=x")).to eq("http://h?oauth_token=***")
    end

    it "keeps non-sensitive query string parameters untouched" do
      expect(diagnostics.mask("DATABASE_URL", "postgresql://db:5432/lago?sslmode=require"))
        .to eq("postgresql://db:5432/lago?sslmode=require")
      expect(diagnostics.mask("SOME_URL", "http://h?monkey=banana")).to eq("http://h?monkey=banana")
      expect(diagnostics.mask("SOME_URL", "http://h?design=modern")).to eq("http://h?design=modern")
      expect(diagnostics.mask("SOME_URL", "http://h?oauth_state=xyz")).to eq("http://h?oauth_state=xyz")
      expect(diagnostics.mask("SOME_URL", "http://h?pool_size=5")).to eq("http://h?pool_size=5")
    end

    it "scrubs values with invalid UTF-8 bytes instead of raising" do
      malformed = ("x" + 255.chr).force_encoding("UTF-8")

      expect { diagnostics.mask("SOME_URL", malformed) }.not_to raise_error
      expect(diagnostics.mask("SOME_URL", malformed)).to eq("x�")
    end

    it "scrubs keys with invalid UTF-8 bytes and still masks secret-matching ones" do
      malformed_key = ("SECRET_" + 255.chr).force_encoding("UTF-8")

      expect { diagnostics.mask(malformed_key, "value") }.not_to raise_error
      expect(diagnostics.mask(malformed_key, "value")).to eq("***")
    end

    it "converts nil values to an empty string" do
      expect(diagnostics.mask("SOME_VALUE", nil)).to eq("")
    end

    it "redacts every URL when the value contains several" do
      expect(diagnostics.mask("SOME_URLS", "a=redis://u:p@h1:6379 b=amqp://u:p@h2:5672"))
        .to eq("a=redis://***@h1:6379 b=amqp://***@h2:5672")
    end

    it "passes plain values through" do
      expect(diagnostics.mask("RAILS_ENV", "production")).to eq("production")
    end
  end
end
