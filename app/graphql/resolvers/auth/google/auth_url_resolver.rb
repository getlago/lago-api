# frozen_string_literal: true

module Resolvers
  module Auth
    module Google
      class AuthUrlResolver < Resolvers::BaseResolver
        graphql_name 'GooGleAuthUrl'
        description 'Query a single add-on of an organization'

        type Types::Auth::Google::AuthUrl, null: false

        def resolve(**_args)
          ::Auth::GoogleService
            .new
            .authorize_url(context[:request])
        end
      end
    end
  end
end
