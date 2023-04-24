# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invites::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:revoked_membership) do
    create(
      :membership,
      organization: membership.organization,
      status: :revoked,
    )
  end
  let(:organization) { membership.organization }
  let(:email) { Faker::Internet.email }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateInviteInput!) {
        createInvite(input: $input) {
          id
          token
          email
        }
      }
    GQL
  end

  it 'creates an invite for a new user' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          email:,
        },
      },
    )

    data = result['data']['createInvite']

    expect(data['email']).to eq(email)
    expect(data['token']).to be_present
  end

  it 'creates an invite for a revoked user' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          email: revoked_membership.user.email,
        },
      },
    )

    data = result['data']['createInvite']

    expect(data['email']).to eq(revoked_membership.user.email)
    expect(data['token']).to be_present
  end

  it 'returns an error if invite already exists' do
    create(:invite, email:, recipient: membership, organization: membership.organization)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          email:,
        },
      },
    )

    expect(result['errors'].first['extensions']['status']).to eq(422)
    expect(result['errors'].first['extensions']['code']).to eq('unprocessable_entity')
    expect(result['errors'].first['extensions']['details']['invite']).to eq(['invite_already_exists'])
  end

  it 'returns an error if email already attached to a user of the organization' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          email: membership.user.email,
        },
      },
    )

    expect(result['errors'].first['extensions']['status']).to eq(422)
    expect(result['errors'].first['extensions']['code']).to eq('unprocessable_entity')
    expect(result['errors'].first['extensions']['details']['email']).to eq(['email_already_used'])
  end
end
