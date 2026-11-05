# frozen_string_literal: true

require "rails_helper"

module GuardsSignupAttemptsSpec
  class ThingType < Types::BaseObject
    field :ok, Boolean, null: false
  end

  class StartThing < Mutations::BaseMutation
    include GuardsSignupAttempts

    graphql_name "GuardsSignupAttemptsStartThing"
    captcha_token_argument
    type ThingType

    def resolve(captcha_token: nil)
      signup_guard_error(:sign_up, captcha_token:) || {ok: true}
    end
  end

  class ConfirmThing < Mutations::BaseMutation
    include GuardsSignupAttempts

    graphql_name "GuardsSignupAttemptsConfirmThing"
    captcha_token_argument
    type ThingType

    def resolve(captcha_token: nil)
      signup_guard_error(:confirm_signup_email_with_password, captcha_token:) || {ok: true}
    end
  end

  class CheckThing < Resolvers::BaseResolver
    include GuardsSignupAttempts

    type ThingType, null: false

    def resolve
      signup_guard_error(:signup_status) || {ok: true}
    end
  end

  class MutationType < Types::BaseObject
    field :start_thing, mutation: StartThing
    field :confirm_thing, mutation: ConfirmThing
  end

  class QueryType < Types::BaseObject
    field :check_thing, resolver: CheckThing
  end

  class TestSchema < LagoApiSchema
    query(QueryType)
    mutation(MutationType)
  end
end

RSpec.describe GuardsSignupAttempts do
  let(:remote_ip) { "203.0.113.10" }
  let(:captcha_token) { "captcha-token" }
  let(:siteverify) { stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP) }

  before do
    Auth::AttemptsThrottle.store = ActiveSupport::Cache::MemoryStore.new
    siteverify
  end

  def run(query, ip: remote_ip, token: captcha_token)
    request = instance_double(ActionDispatch::Request, remote_ip: ip)
    GuardsSignupAttemptsSpec::TestSchema.execute(query, variables: {token:}, context: {request:})
  end

  def start(ip: remote_ip, token: captcha_token)
    run("mutation($token: String) { startThing(input: {captchaToken: $token}) { ok } }", ip:, token:)
  end

  def code(result)
    result["errors"]&.first&.dig("extensions", "code")
  end

  it "lets a verified attempt through and sends the client IP to Google" do
    expect(start["data"]["startThing"]).to eq("ok" => true)
    expect(a_request(:post, Signups::VerifyCaptchaService::SITEVERIFY_URL).with(body: hash_including("remoteip" => remote_ip)))
      .to have_been_made.once
  end

  it "refuses a missing captcha token with captcha_failed, not a schema error" do
    expect(start(token: nil)["errors"].first["extensions"]).to eq("status" => 403, "code" => "captcha_failed")
  end

  it "refuses a low score and answers an outage with captcha_unavailable" do
    stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP, score: 0.1)
    expect(code(start)).to eq("captcha_failed")

    stub_request(:post, Signups::VerifyCaptchaService::SITEVERIFY_URL).to_timeout
    expect(start["errors"].first["extensions"]).to eq("status" => 500, "code" => "captcha_unavailable")
  end

  it "limits signup starts per network once the captcha passes" do
    expect(Array.new(10) { code(start) }).to all(be_nil)

    expect(start["errors"].first["extensions"]).to eq("status" => 429, "code" => "too_many_requests")
  end

  it "does not count refused captchas against the signup budget" do
    10.times { start(token: nil) }

    expect(Array.new(10) { code(start) }).to all(be_nil)
  end

  it "bounds the calls to Google before checking the captcha" do
    60.times { start }

    expect(code(start)).to eq("too_many_requests")
    expect(siteverify).to have_been_requested.times(60)
  end

  it "applies the daily limit across hours" do
    3.times do |hour|
      travel_to((hour * 61).minutes.from_now) { 10.times { start } }
    end

    travel_to(4.hours.from_now) { expect(code(start)).to eq("too_many_requests") }
  end

  it "shares the limit within one IPv6 /64 and keeps other /64s apart" do
    10.times { start(ip: "2001:db8:1:2::a") }

    expect(code(start(ip: "2001:db8:1:2::b"))).to eq("too_many_requests")
    expect(code(start(ip: "2001:db8:1:3::a"))).to be_nil
  end

  it "limits one IPv6 /48 across its /64s" do
    50.times { start(ip: "2001:db8:1:#{it.to_s(16)}::a") }

    expect(code(start(ip: "2001:db8:1:ff::a"))).to eq("too_many_requests")
  end

  it "keeps attempts refused by a network's own limit out of its /48's budget" do
    60.times { start(ip: "2001:db8:1:2::a") } # 10 pass, then the /64 is over its limit

    expect(code(start(ip: "2001:db8:1:3::a"))).to be_nil
  end

  it "keeps attempts refused by the hourly limit out of the daily budget" do
    30.times { start } # 10 pass, 20 refused

    travel_to(61.minutes.from_now) { expect(Array.new(10) { code(start) }).to all(be_nil) }
  end

  it "verifies the cross-device confirm with its own action and limit" do
    stub_recaptcha_siteverify(action: Signups::VerifyCaptchaService::SIGNUP_CONFIRM)
    confirm = -> { run("mutation($token: String) { confirmThing(input: {captchaToken: $token}) { ok } }") }

    expect(Array.new(20) { code(confirm.call) }).to all(be_nil)
    expect(code(confirm.call)).to eq("too_many_requests")
  end

  it "limits lookups without calling Google" do
    expect(Array.new(60) { code(run("query { checkThing { ok } }")) }).to all(be_nil)

    expect(code(run("query { checkThing { ok } }"))).to eq("too_many_requests")
    expect(siteverify).not_to have_been_requested
  end

  context "when the throttling store is unavailable" do
    before { Auth::AttemptsThrottle.store = ActiveSupport::Cache::NullStore.new }

    it "stops counting but still refuses a missing captcha" do
      10.times { start }

      expect(code(start)).to be_nil
      expect(code(start(token: nil))).to eq("captcha_failed")
    end
  end

  describe "limit reports" do
    before { allow(Rails.logger).to receive(:warn).and_call_original }

    it "logs the rules without the IP", :sentry do
      61.times { run("query { checkThing { ok } }") }

      expect(Rails.logger).to have_received(:warn).with("GuardsSignupAttempts limit reached rules=signup_status_per_ip trusted_ip=false")
      expect(sentry_events).to be_empty
    end

    it "warns once per window when the client IP is a trusted proxy address", :sentry do
      70.times { run("query { checkThing { ok } }", ip: "10.0.0.5") }

      expect(sentry_events.map(&:message)).to eq(["Signup attempts limit reached from a trusted proxy address"])
    end
  end

  describe "GUARDS" do
    it "names only existing rules and reCAPTCHA actions" do
      guards = described_class::GUARDS.values
      rules = (guards.flat_map(&:rules) + described_class::CAPTCHA_RULES).uniq

      expect(rules - Auth::AttemptsThrottle::RULES.keys).to be_empty
      expect(guards.filter_map(&:captcha_action) - Signups::VerifyCaptchaService::ACTIONS).to be_empty
    end

    it "raises on an unknown endpoint" do
      expect { described_class::GUARDS.fetch(:sign_in) }.to raise_error(KeyError)
    end
  end
end
