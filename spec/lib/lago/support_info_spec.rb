# frozen_string_literal: true

require "rails_helper"
require "lago/support_info"

RSpec.describe Lago::SupportInfo do
  subject(:support_info) { described_class.new(output:) }

  let(:output) { StringIO.new }
  let(:report) { output.string }

  describe "#call" do
    before { stub_request(:post, %r{clickhouse}).to_return(status: 500) }

    it "prints the banners and all six section headers" do
      support_info.call

      expect(report).to include("LAGO SUPPORT DIAGNOSTIC")
      expect(report).to include("1. VERSION AND BUILD")
      expect(report).to include("2. ENVIRONMENT")
      expect(report).to include("3. CONFIGURATION")
      expect(report).to include("4. HEALTH AND QUEUE STATE")
      expect(report).to include("5. DATA SHAPE (counts only, no content)")
      expect(report).to include("6. RECENT ERRORS")
      expect(report).to include("END OF DIAGNOSTIC")
    end

    it "labels the row counts as estimated" do
      support_info.call

      expect(report).to include("## Key Table Row Counts (estimated)")
    end

    context "when LAGO_VERSION contains a version tag instead of a SHA" do
      before do
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(Rails.root.join("LAGO_VERSION")).and_return("v1.20.0\n")
      end

      it "does not label the tag as a commit SHA" do
        support_info.call

        expect(report).to include("Commit SHA     : (not available, version tag build)")
      end
    end

    context "when a probe raises" do
      before do
        allow(Sidekiq::Queue).to receive(:all).and_raise(StandardError, "redis is down")
      end

      it "prints an error marker and still completes the report" do
        expect { support_info.call }.not_to raise_error

        expect(report).to include("error: StandardError - redis is down")
        expect(report).to include("END OF DIAGNOSTIC")
      end
    end
  end

  describe "#mask" do
    it "masks values of secret-matching keys" do
      expect(support_info.mask("LAGO_SMTP_PASSWORD", "hunter2")).to eq("***")
      expect(support_info.mask("SECRET_KEY_BASE", "abc123")).to eq("***")
      expect(support_info.mask("LAGO_DATA_API_BEARER_TOKEN", "abc123")).to eq("***")
    end

    it "masks values of client_id and license keys" do
      expect(support_info.mask("GOCARDLESS_CLIENT_ID", "OJWZfIzwIwf5Ww6W")).to eq("***")
      expect(support_info.mask("LAGO_LICENSE", "lic-123")).to eq("***")
    end

    it "redacts URL userinfo credentials while keeping host and port visible" do
      expect(support_info.mask("DATABASE_URL", "postgresql://lago:changeme@db:5432/lago"))
        .to eq("postgresql://***@db:5432/lago")
      expect(support_info.mask("REDIS_URL", "redis://user@redis:6379"))
        .to eq("redis://***@redis:6379")
    end

    it "redacts the whole userinfo when the password contains an @" do
      expect(support_info.mask("DATABASE_URL", "postgresql://user:p@ss@db:5432/lago"))
        .to eq("postgresql://***@db:5432/lago")
    end

    it "redacts userinfo credentials in front of an IPv6 host" do
      expect(support_info.mask("REDIS_URL", "redis://user:pass@[::1]:6379"))
        .to eq("redis://***@[::1]:6379")
    end

    it "keeps URL values without userinfo untouched" do
      expect(support_info.mask("LAGO_API_URL", "http://localhost:3000"))
        .to eq("http://localhost:3000")
      expect(support_info.mask("DATABASE_URL", "postgresql://db:5432/lago"))
        .to eq("postgresql://db:5432/lago")
    end

    it "redacts sensitive query string parameters" do
      expect(support_info.mask("DATABASE_URL", "postgresql://lago@db/lago?password=secret123"))
        .to eq("postgresql://***@db/lago?password=***")
      expect(support_info.mask("REDIS_URL", "redis://redis:6379/0?user=lago&access_token=abc123"))
        .to eq("redis://redis:6379/0?user=lago&access_token=***")
    end

    it "keeps non-sensitive query string parameters untouched" do
      expect(support_info.mask("DATABASE_URL", "postgresql://db:5432/lago?sslmode=require"))
        .to eq("postgresql://db:5432/lago?sslmode=require")
    end

    it "passes plain values through" do
      expect(support_info.mask("RAILS_ENV", "production")).to eq("production")
    end
  end
end
