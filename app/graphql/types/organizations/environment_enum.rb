# frozen_string_literal: true

module Types
  module Organizations
    class EnvironmentEnum < Types::BaseEnum
      graphql_name "OrganizationEnvironmentEnum"
      description "Whether an organization is a production organization or the sandbox of one"

      Organization::ENVIRONMENTS.values.each do |environment|
        value environment, description: "#{environment.capitalize} organization"
      end
    end
  end
end
