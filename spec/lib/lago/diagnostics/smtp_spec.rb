# frozen_string_literal: true

require "rails_helper"
require "lago/diagnostics"

RSpec.describe Lago::Diagnostics, "#smtp" do
  subject(:smtp_settings) { application.config.action_mailer.smtp_settings }

  let(:application) { Class.new(Rails::Application).instance }
  let(:environment) { {} }
  let(:output) { StringIO.new }
  let(:diagnostics) { described_class.new(output:) }
  let(:smtp_report) do
    diagnostics.send(:smtp)
    output.string
  end

  around do |example|
    env_keys = %w[LAGO_SMTP_ADDRESS LAGO_SMTP_AUTHENTICATION LAGO_SMTP_ENABLE_STARTTLS_AUTO]
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
      expect(smtp_settings).to include(authentication: "login", enable_starttls_auto: true)

      expect(smtp_report).to match(/Authentication\s+: login/)
      expect(smtp_report).to match(/STARTTLS\s+: enabled/)
    end
  end

  context "when SMTP authentication is explicitly empty" do
    let(:environment) { {"LAGO_SMTP_AUTHENTICATION" => ""} }

    it "disables authentication" do
      expect(smtp_settings[:authentication]).to be_nil
      expect(smtp_report).to match(/Authentication\s+: none/)
    end
  end

  context "when STARTTLS is explicitly disabled" do
    let(:environment) { {"LAGO_SMTP_ENABLE_STARTTLS_AUTO" => "false"} }

    it "disables STARTTLS" do
      expect(smtp_settings[:enable_starttls_auto]).to be(false)
      expect(smtp_report).to match(/STARTTLS\s+: disabled/)
    end
  end

  context "when the STARTTLS variable is empty" do
    let(:environment) { {"LAGO_SMTP_ENABLE_STARTTLS_AUTO" => ""} }

    it "keeps STARTTLS enabled" do
      expect(smtp_settings[:enable_starttls_auto]).to be(true)
      expect(smtp_report).to match(/STARTTLS\s+: enabled/)
    end
  end
end
