# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Forwarded headers" do # rubocop:disable RSpec/DescribeClass
  def remote_ip(headers)
    app = ->(env) { [200, {}, [ActionDispatch::Request.new(env).remote_ip]] }
    middleware = ActionDispatch::RemoteIp.new(app, true, ActionDispatch::RemoteIp::TRUSTED_PROXIES)
    env = Rack::MockRequest.env_for("/", {"REMOTE_ADDR" => "10.0.0.1"}.merge(headers))

    middleware.call(env).last.first
  end

  it "reads only X-Forwarded-* headers" do
    expect(Rack::Request.forwarded_priority).to eq([:x_forwarded])
  end

  it "ignores a client-supplied Forwarded header" do
    expect(remote_ip("HTTP_FORWARDED" => "for=6.6.6.6")).to eq("10.0.0.1")
  end

  it "uses X-Forwarded-For when both headers disagree" do
    headers = {"HTTP_FORWARDED" => "for=6.6.6.6", "HTTP_X_FORWARDED_FOR" => "1.2.3.4"}

    expect(remote_ip(headers)).to eq("1.2.3.4")
  end
end
