# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Invites::Accept do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }
  let(:password) { Faker::Internet.password }

  let(:mutation) do
    <<~GQL
      mutation($input: AcceptInviteInput!) {
        acceptInvite(input: $input) {
          token
          user {
            id
            email
          }
        }
      }
    GQL
  end

  describe "Invite revoke mutation" do
    context "with a new user" do
      let(:invite) { create(:invite, organization:) }

      it "accepts the invite" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: mutation,
          variables: {
            input: {
              email: invite.email,
              password:,
              token: invite.token
            }
          }
        )

        data = result["data"]["acceptInvite"]

        expect(data["user"]["email"]).to eq(invite.email)
        expect(data["token"]).to be_present

        expect(Utils::AuthToken.decode(token: data["token"])).to include("login_method" => "email_password")
      end
    end

    context "when invite is revoked" do
      let(:invite) { create(:invite, organization:, status: :revoked) }

      it "returns an error" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: mutation,
          variables: {
            input: {
              email: invite.email,
              password:,
              token: invite.token
            }
          }
        )

        expect(result["errors"].first["extensions"]["status"]).to eq(404)
        expect(result["errors"].first["extensions"]["code"]).to eq("not_found")
        expect(result["errors"].first["extensions"]["details"]["invite"]).to eq(["not_found"])
      end
    end

    context "when invite is already accepted" do
      let(:invite) { create(:invite, organization:, status: :accepted) }

      it "returns an error" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          query: mutation,
          variables: {
            input: {
              email: invite.email,
              password:,
              token: invite.token
            }
          }
        )

        expect(result["errors"].first["extensions"]["status"]).to eq(404)
        expect(result["errors"].first["extensions"]["code"]).to eq("not_found")
        expect(result["errors"].first["extensions"]["details"]["invite"]).to eq(["not_found"])
      end
    end

    context "with attempts throttling" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }
      let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10") }
      let(:invite) { create(:invite, organization:) }

      before { allow(Auth::AttemptsThrottle).to receive(:store).and_return(cache) }

      it "limits attempts per client IP" do
        20.times do
          execute_graphql(query: mutation, request:, variables: {input: {email: invite.email, password:, token: "invalid"}})
        end

        result = execute_graphql(query: mutation, request:, variables: {input: {email: invite.email, password:, token: invite.token}})

        expect(result["errors"].first.dig("extensions", "code")).to eq("too_many_requests")
      end
    end
  end
end
