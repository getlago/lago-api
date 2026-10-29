# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sentry initializer" do # rubocop:disable RSpec/DescribeClass
  let(:configuration) { Sentry::Configuration.new }
  let(:event) do
    Sentry::ErrorEvent.new(configuration:).tap do |event|
      event.rack_env = Rack::MockRequest.env_for("/cable", "HTTP_SEC_WEBSOCKET_PROTOCOL" => "actioncable-v1-json, lago-token.secret")
    end
  end

  def header_values
    event.request.headers.values.join(" ")
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SENTRY_DSN").and_return("https://key@sentry.example.com/1")
    allow(Sentry).to receive(:init).and_yield(configuration)

    load Rails.root.join("config/initializers/sentry.rb")
  end

  it "drops the cable token from the headers of an error" do
    expect(header_values).to include("lago-token.secret")

    configuration.before_send.call(event, {})

    expect(header_values).not_to include("lago-token")
  end

  it "drops the cable token from the headers of a transaction" do
    expect(header_values).to include("lago-token.secret")

    configuration.before_send_transaction.call(event, {})

    expect(header_values).not_to include("lago-token")
  end
end
