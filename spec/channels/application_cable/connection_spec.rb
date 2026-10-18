# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }
  let(:token) { Utils::AuthToken.encode(user:) }

  def connect_with(protocols)
    connect "/cable", headers: {"Sec-WebSocket-Protocol" => protocols}
  end

  it "authenticates the user from the token subprotocol" do
    connect_with("actioncable-v1-json, actioncable-unsupported, lago-token.#{token}")

    expect(connection.current_user).to eq(user)
    expect(connection.auth_error_code).to be_nil
  end

  it "accepts the connection without a user when no token is sent" do
    connect_with("actioncable-v1-json, actioncable-unsupported")

    expect(connection.current_user).to be_nil
    expect(connection.auth_error_code).to be_nil
  end

  it "ignores an invalid token" do
    connect_with("actioncable-v1-json, lago-token.invalid")

    expect(connection.current_user).to be_nil
    expect(connection.auth_error_code).to be_nil
  end

  it "flags an expired token" do
    expired_token = travel_to(4.hours.ago) { Utils::AuthToken.encode(user:) }
    connect_with("actioncable-v1-json, lago-token.#{expired_token}")

    expect(connection.current_user).to be_nil
    expect(connection.auth_error_code).to eq("expired_jwt_token")
  end
end
