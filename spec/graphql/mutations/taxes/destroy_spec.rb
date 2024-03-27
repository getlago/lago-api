# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Taxes::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyTaxInput!) {
        destroyTax(input: $input) { id }
      }
    GQL
  end

  before { tax }

  it "destroys a tax" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {input: {id: tax.id}}
      )
    end.to change(Tax, :count).by(-1)
  end

  context "without current_organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {input: {id: tax.id}}
      )

      expect_forbidden_error(result)
    end
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {input: {id: tax.id}}
      )

      expect_unauthorized_error(result)
    end
  end
end
