# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /cable" do
  subject(:status) { server.call(Rack::MockRequest.env_for("/cable", websocket_headers.merge("HTTP_ORIGIN" => origin))).first }

  let(:application) { Class.new(Rails::Application).instance }
  let(:server) do
    production_config = application.config.action_cable
    config = ActionCable::Server::Configuration.new
    config.connection_class = -> { ApplicationCable::Connection }
    config.allowed_request_origins = production_config.allowed_request_origins
    config.disable_request_forgery_protection = production_config.disable_request_forgery_protection
    config.logger = Logger.new(nil)
    ActionCable::Server::Base.new(config:)
  end
  let(:websocket_headers) do
    {
      "HTTP_HOST" => "api.example.com",
      "HTTP_CONNECTION" => "Upgrade",
      "HTTP_UPGRADE" => "websocket",
      "HTTP_SEC_WEBSOCKET_KEY" => "dGhlIHNhbXBsZSBub25jZQ==",
      "HTTP_SEC_WEBSOCKET_VERSION" => "13"
    }
  end

  # Origins are only checked in staging and production, so the spec runs with the production config.
  before do
    original_application = Rails.application
    allow(Rails).to receive(:application).and_return(application)
    load Rails.root.join("config/environments/production.rb")
    allow(Rails).to receive(:application).and_return(original_application)
  end

  context "when the socket is opened from the front end" do
    let(:origin) { LagoApi::Application.origin_of(Rails.application.config.lago_front_url) }

    it "accepts the handshake" do
      expect(status).not_to eq(404)
    end
  end

  context "when the socket is opened from another origin" do
    let(:origin) { "https://evil.example.com" }

    it "rejects the handshake" do
      expect(status).to eq(404)
    end
  end
end
