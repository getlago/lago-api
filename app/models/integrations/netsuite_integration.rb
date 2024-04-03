# frozen_string_literal: true

module Integrations
  class NetsuiteIntegration < BaseIntegration

    validates :connection_id, :client_secret, :client_id, :account_id, presence: true

    def connection_id=(connection_id)
      push_to_secrets(key: 'connection_id', value: connection_id)
    end

    def connection_id
      get_from_secrets('connection_id')
    end

    def client_secret=(client_secret)
      push_to_secrets(key: 'client_secret', value: client_secret)
    end

    def client_secret
      get_from_secrets('client_secret')
    end

    def account_id=(value)
      push_to_settings(key: 'account_id', value:)
    end

    def account_id
      get_from_settings('account_id')
    end

    def client_id=(value)
      push_to_settings(key: 'client_id', value:)
    end

    def client_id
      get_from_settings('client_id')
    end
  end
end
