# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::LoginUser do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let(:user) { membership.user }
  let(:mutation) do
    <<~GQL
      mutation($input: LoginUserInput!) {
        loginUser(input: $input) {
          token
          user {
            id
            email
          }
        }
      }
    GQL
  end

  it "returns token and user" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email: user.email,
          password: "ILoveLago"
        }
      }
    )

    result_data = result["data"]["loginUser"]

    expect(result_data["token"]).to be_present
    expect(result_data["user"]["id"]).to eq(user.id)
  end

  context "with bad credentials" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: user.email,
            password: "badpassword"
          }
        }
      )

      expect_unprocessable_entity(result)
      expect(result["errors"].first.dig("extensions", "details").keys).to include("base")
      expect(result["errors"].first.dig("extensions", "details", "base")).to include("incorrect_login_or_password")
    end
  end

  context "with revoked membership" do
    let(:revoked_membership) { create(:membership, status: :revoked) }

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: revoked_membership.user.email,
            password: "ILoveLago"
          }
        }
      )

      expect_unprocessable_entity(result)
      expect(result["errors"].first.dig("extensions", "details").keys).to include("base")
      expect(result["errors"].first.dig("extensions", "details", "base")).to include("incorrect_login_or_password")
    end
  end

  context "with attempts throttling" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:request) { request_from("203.0.113.10") }

    before { Auth::AttemptsThrottle.store = cache }

    def request_from(ip)
      instance_double(ActionDispatch::Request, remote_ip: ip)
    end

    def login(password, email: user.email, request: self.request)
      execute_graphql(query: mutation, request:, variables: {input: {email:, password:}})
    end

    it "locks the email for the IP after 10 failed attempts, even with the right password" do
      10.times { login("badpassword") }

      result = login("ILoveLago")

      expect(result["data"]["loginUser"]).to be_nil
      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      expect(result["errors"].first.dig("extensions", "status")).to eq(429)
    end

    context "when failed attempts use invisible characters or dash lookalikes" do
      let(:user) { create(:membership, user: create(:user, email: "jane-doe@example.com")).user }

      it "locks the email" do
        variants = [
          "jane-d\u200Boe@example.com",
          "\u200Djane-doe@example.com",
          "jane-doe@example.com\uFEFF",
          "jane\u2013doe@example.com",
          "jane\u2212doe@example.com"
        ]
        10.times { |i| login("badpassword", email: variants[i % variants.size]) }

        result = login("ILoveLago")

        expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      end
    end

    it "does not lock the email for another IP" do
      10.times { login("badpassword") }

      result = login("ILoveLago", request: request_from("198.51.100.20"))

      expect(result["data"]["loginUser"]["token"]).to be_present
    end

    it "locks the email after 100 failed attempts spread over many IPs" do
      100.times { |i| login("badpassword", request: request_from("198.51.100.#{i}")) }

      result = login("ILoveLago", request: request_from("192.0.2.1"))

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end

    it "does not count attempts over the IP limit against the email" do
      30.times { |i| login("badpassword", email: "unknown-#{i}@example.com") }
      100.times { login("badpassword") }

      expect(login("ILoveLago", request: request_from("198.51.100.20"))["data"]["loginUser"]["token"]).to be_present
    end

    context "when the password is checked" do
      let(:attempts_seen_during_check) { [] }

      before do
        allow(UsersService).to receive(:call).and_wrap_original do |original, *args|
          attempts_seen_during_check << %i[login_per_email_and_ip login_per_email].map do |rule_name|
            identifiers = (rule_name == :login_per_email_and_ip) ? [user.email, request.remote_ip] : [user.email]
            cache.read(Auth::AttemptsThrottle.cache_key(rule_name, *identifiers), raw: true).to_i
          end
          original.call(*args)
        end
      end

      it "has already counted the attempt" do
        login("badpassword")

        expect(attempts_seen_during_check).to eq([[1, 1]])
      end
    end

    it "resets the failure count after a successful login" do
      9.times { login("badpassword") }
      login("ILoveLago")
      9.times { login("badpassword") }

      expect(login("ILoveLago")["data"]["loginUser"]["token"]).to be_present
    end

    it "limits attempts per client IP across emails" do
      30.times { |i| login("badpassword", email: "unknown-#{i}@example.com") }

      result = login("ILoveLago")

      expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
    end
  end
end
