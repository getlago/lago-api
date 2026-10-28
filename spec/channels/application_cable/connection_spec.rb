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

  it "redacts the token from the env once read" do
    connect_with("actioncable-v1-json, actioncable-unsupported, lago-token.#{token}")

    expect(connection.env["HTTP_SEC_WEBSOCKET_PROTOCOL"])
      .to eq("actioncable-v1-json, actioncable-unsupported, lago-token.[FILTERED]")
  end

  it "tracks the expiration of the token" do
    connect_with("actioncable-v1-json, lago-token.#{token}")

    expect(connection.token_expired?).to be(false)
    travel_to(4.hours.from_now) { expect(connection.token_expired?).to be(true) }
  end

  it "rejects the connection when no token is sent" do
    expect { connect_with("actioncable-v1-json, actioncable-unsupported") }.to have_rejected_connection
  end

  it "rejects the connection when no subprotocol is sent" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects an invalid token" do
    expect { connect_with("actioncable-v1-json, lago-token.invalid") }.to have_rejected_connection
  end

  it "keeps the session claims of the token" do
    sso_token = Utils::AuthToken.encode(user:, login_method: "okta", sso_organization_id: "org-id", sso_issuer: "https://sso.okta.com")
    connect_with("actioncable-v1-json, lago-token.#{sso_token}")

    expect(connection.session_claims).to eq(login_method: "okta", sso_organization_id: "org-id", sso_issuer: "https://sso.okta.com")
  end

  it "rejects an SSO session without its claims" do
    sso_token = Utils::AuthToken.encode(user:, login_method: "okta")

    expect { connect_with("actioncable-v1-json, lago-token.#{sso_token}") }.to have_rejected_connection
  end

  it "rejects an expired token" do
    expired_token = travel_to(4.hours.ago) { Utils::AuthToken.encode(user:) }

    expect { connect_with("actioncable-v1-json, lago-token.#{expired_token}") }.to have_rejected_connection
  end
end
