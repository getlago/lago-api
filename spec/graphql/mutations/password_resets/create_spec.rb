# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PasswordResets::Create do
  let(:user) { create(:user) }
  let(:email) { user.email }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePasswordResetInput!) {
        createPasswordReset(input: $input) {
          id
        }
      }
    GQL
  end

  it "creates a password reset for a user" do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email:
        }
      }
    )

    data = result["data"]["createPasswordReset"]

    expect(data["id"]).to be_present
  end
end
