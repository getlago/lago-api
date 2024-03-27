# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AddOns::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyAddOnInput!) {
        destroyAddOn(input: $input) { id }
      }
    GQL
  end

  it "deletes an add-on" do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {id: add_on.id}
      }
    )

    data = result["data"]["destroyAddOn"]
    expect(data["id"]).to eq(add_on.id)
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {id: add_on.id}
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
