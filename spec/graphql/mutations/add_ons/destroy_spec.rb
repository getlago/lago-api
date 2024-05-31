# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AddOns::Destroy, type: :graphql do
  let(:required_permission) { 'addons:delete' }
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

  it_behaves_like 'requires current user'
  it_behaves_like 'requires permission', 'addons:delete'

  it 'deletes an add-on' do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: add_on.id}
      }
    )

    data = result['data']['destroyAddOn']
    expect(data['id']).to eq(add_on.id)
  end
end
