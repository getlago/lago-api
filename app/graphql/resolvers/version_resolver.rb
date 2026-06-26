# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Resolvers
  class VersionResolver < Resolvers::BaseResolver
    description "Retrieve the version of the application"

    type Types::Utils::CurrentVersion, null: false

    def resolve
      LAGO_VERSION
    end
  end
end
