# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PasswordResets::Reset do
  let(:membership) { create(:membership, user: create(:user, password: "HelloLago!1")) }
  let(:password_reset) { create(:password_reset, user: membership.user) }

  let(:mutation) do
    <<~GQL
      mutation($input: ResetPasswordInput!) {
        resetPassword(input: $input) {
          token
        }
      }
    GQL
  end

  it "returns the auth token after a password reset" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          newPassword: "HelloLago!2",
          token: password_reset.token
        }
      }
    )

    data = result["data"]["resetPassword"]

    expect(data["token"]).to be_present
  end

  context "when the password reset is expired" do
    let(:expired_password_reset) do
      create(:password_reset, user: membership.user, expire_at: Time.current - 1.minute)
    end

    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            newPassword: "HelloLago!3",
            token: expired_password_reset.token
          }
        }
      )

      expect_not_found(result)
    end
  end
end
