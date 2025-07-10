# frozen_string_literal: true

RSpec.shared_context "with graphql query context" do
  subject(:execute) do
    variables[:input] = input if respond_to?(:input)

    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }
end
