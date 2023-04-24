# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::VersionResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        currentVersion { number githubUrl }
      }
    GQL
  end

  it 'returns the currentVersion' do
    result = execute_graphql(query:)

    version_response = result['data']['currentVersion']

    aggregate_failures do
      expect(version_response['number']).to be_present
      expect(version_response['githubUrl']).to start_with(Utils::VersionService::GITHUB_BASE_URL)
    end
  end
end
