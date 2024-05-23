# frozen_string_literal: true

require 'entitlement/authorization_controller'

namespace :entitlement do
  namespace :v1 do
    get '/authorization', to: 'authorization#index'
  end
end
