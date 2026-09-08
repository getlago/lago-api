# frozen_string_literal: true

require "rails_helper"
require "lago/diagnostics"

RSpec.describe Lago::Diagnostics, "#smtp" do
  subject(:smtp_settings) { application.config.action_mailer.smtp_settings }

  let(:application) { Class.new(Rails::Application).instance }
  let(:credentials) { {"LAGO_SMTP_USERNAME" => "smtp-user", "LAGO_SMTP_PASSWORD" => "smtp-password"} }
  let(:environment) { credentials }
  let(:output) { StringIO.new }
  let(:diagnostics) { described_class.new(output:) }
  let(:smtp_report) do
    diagnostics.send(:smtp)
    output.string
  end

  around do |example|
    env_keys = %w[
      LAGO_SMTP_ADDRESS LAGO_SMTP_AUTHENTICATION LAGO_SMTP_ENABLE_STARTTLS_AUTO
      LAGO_SMTP_USERNAME LAGO_SMTP_PASSWORD
    ]
    previous_environment = env_keys.index_with { |key| ENV[key] }

    env_keys.each { |key| ENV.delete(key) }
    ENV["LAGO_SMTP_ADDRESS"] = "smtp.example.com"
    environment.each { |key, value| ENV[key] = value }
    example.run
  ensure
    previous_environment&.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  before do
    original_application = Rails.application
    allow(Rails).to receive(:application).and_return(application)
    load Rails.root.join("config/environments/production.rb")
    allow(Rails).to receive(:application).and_return(original_application)
  end

  context "when the SMTP security variables are absent" do
    it "keeps authentication and STARTTLS enabled" do
      expect(smtp_settings).to include(authentication: "login", user_name: "smtp-user", enable_starttls_auto: true)

      expect(smtp_report).to match(/Authentication\s+: login$/)
      expect(smtp_report).to match(/STARTTLS\s+: enabled$/)
    end
  end

  context "when SMTP authentication is explicitly empty" do
    let(:environment) { credentials.merge("LAGO_SMTP_AUTHENTICATION" => "") }

    it "disables authentication and drops the credentials" do
      expect(smtp_settings).to include(authentication: nil, user_name: nil, password: nil)
      expect(smtp_report).to match(/Authentication\s+: none$/)
    end
  end

  context "when SMTP authentication is set to none" do
    let(:environment) { credentials.merge("LAGO_SMTP_AUTHENTICATION" => "none") }

    it "disables authentication and drops the credentials" do
      expect(smtp_settings).to include(authentication: nil, user_name: nil, password: nil)
      expect(smtp_report).to match(/Authentication\s+: none$/)
    end
  end

  context "when SMTP authentication is set to disabled" do
    let(:environment) { credentials.merge("LAGO_SMTP_AUTHENTICATION" => "DISABLED") }

    it "disables authentication regardless of the casing" do
      expect(smtp_settings).to include(authentication: nil, user_name: nil, password: nil)
      expect(smtp_report).to match(/Authentication\s+: none$/)
    end
  end

  context "when SMTP authentication is set to another supported method" do
    let(:environment) { credentials.merge("LAGO_SMTP_AUTHENTICATION" => "cram_md5") }

    it "keeps the requested method" do
      expect(smtp_settings).to include(authentication: "cram_md5", user_name: "smtp-user")
      expect(smtp_report).to match(/Authentication\s+: cram_md5$/)
    end
  end

  context "when SMTP authentication is not supported by net-smtp" do
    let(:environment) { credentials.merge("LAGO_SMTP_AUTHENTICATION" => "lgoin") }

    it "reports the value as invalid" do
      expect(smtp_settings[:authentication]).to eq("lgoin")
      expect(smtp_report).to match(/Authentication\s+: lgoin \(invalid - delivery will fail\)$/)
    end
  end

  context "when STARTTLS is explicitly disabled" do
    let(:environment) { credentials.merge("LAGO_SMTP_ENABLE_STARTTLS_AUTO" => "false") }

    it "disables STARTTLS" do
      expect(smtp_settings[:enable_starttls_auto]).to be(false)
      expect(smtp_report).to match(/STARTTLS\s+: disabled$/)
    end
  end

  context "when the STARTTLS variable is empty" do
    let(:environment) { credentials.merge("LAGO_SMTP_ENABLE_STARTTLS_AUTO" => "") }

    it "keeps STARTTLS enabled" do
      expect(smtp_settings[:enable_starttls_auto]).to be(true)
      expect(smtp_report).to match(/STARTTLS\s+: enabled$/)
    end
  end
end
